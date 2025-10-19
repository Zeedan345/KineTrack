//
//  GeminiAPIFunctions.swift
//  KineTrack
//
//  Created by Zeedan on 10/19/25.
//

import Foundation

private let GEMINI_HOST = "https://generativelanguage.googleapis.com"
private let MODEL = "gemini-2.5-flash" // or "gemini-1.5-flash"

private enum GError: Error { case missingKey, badHTTP(Int, String), noText, badResp, fileAttrs, mime, io }

public func sendPromptWithVideo(
    position: String,
    videoURL: URL,
    completion: @escaping (Result<String, Error>) -> Void
) {
    guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String, !apiKey.isEmpty
    else { completion(.failure(GError.missingKey)); return }

    Task {
        do {
            let fm = FileManager.default
            let attrs = try fm.attributesOfItem(atPath: videoURL.path)
            guard let size = attrs[.size] as? NSNumber else { throw GError.fileAttrs }
            let mime = try mimeType(for: videoURL.pathExtension)

            // Decide inline vs Files API (inline for <= 20MB; else upload)
            let useInline = size.intValue <= 20 * 1024 * 1024

            let videoPart: [String: Any]
            if useInline {
                let bytes = try Data(contentsOf: videoURL, options: .mappedIfSafe)
                videoPart = ["inline_data": ["mime_type": mime, "data": bytes.base64EncodedString()]]
            } else {
                let fileURI = try await uploadFileToGemini(apiKey: apiKey, fileURL: videoURL, mimeType: mime)
                videoPart = ["file_data": ["mime_type": mime, "file_uri": fileURI]]
            }

            let systemText = """
            You are a physical therapy assistant analyzing exercise form from video.
            Focus on spine neutrality, scapular control, knee valgus/varus, and hip shift.
            Return a concise summary with key findings and corrective cues.
            """

            let body: [String: Any] = [
                "system_instruction": ["role": "system", "parts": [["text": systemText]]],
                "contents": [[
                    "role": "user",
                    "parts": [
                        videoPart,
                        ["text": "Exercise position: \(position). Analyze posture and give actionable advice."]
                    ]
                ]],
                // Ask for plain text back (could switch to JSON mode later)
                "generation_config": ["response_mime_type": "text/plain"]
            ]

            var req = URLRequest(url: URL(string: "\(GEMINI_HOST)/v1beta/models/\(MODEL):generateContent")!)
            req.httpMethod = "POST"
            req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode)
            else {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                throw GError.badHTTP(code, String(data: data, encoding: .utf8) ?? "")
            }

            struct Part: Decodable { let text: String? }
            struct Content: Decodable { let parts: [Part] }
            struct Candidate: Decodable { let content: Content }
            struct GenerateResponse: Decodable { let candidates: [Candidate] }

            let decoded = try JSONDecoder().decode(GenerateResponse.self, from: data)
            guard let text = decoded.candidates.first?.content.parts.first?.text, !text.isEmpty
            else { throw GError.noText }

            completion(.success(text))
        } catch {
            completion(.failure(error))
        }
    }
}

// ---------- Helpers ----------

private func mimeType(for ext: String) throws -> String {
    switch ext.lowercased() {
    case "mp4": return "video/mp4"
    case "mov", "qt": return "video/quicktime"
    case "m4v": return "video/x-m4v"
    default: throw GError.mime
    }
}

// Files API (resumable) upload; returns file_uri
private func uploadFileToGemini(apiKey: String, fileURL: URL, mimeType: String) async throws -> String {
    let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)

    // 1) Start resumable upload
    var start = URLRequest(url: URL(string: "\(GEMINI_HOST)/upload/v1beta/files")!)
    start.httpMethod = "POST"
    start.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
    start.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
    start.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
    start.setValue("\(data.count)", forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
    start.setValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
    start.setValue("application/json", forHTTPHeaderField: "Content-Type")
    start.httpBody = try JSONSerialization.data(withJSONObject: ["file": ["display_name": fileURL.lastPathComponent]])

    let (startData, startResp) = try await URLSession.shared.data(for: start)
    guard let http = startResp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        let code = (startResp as? HTTPURLResponse)?.statusCode ?? -1
        throw GError.badHTTP(code, String(data: startData, encoding: .utf8) ?? "")
    }
    let uploadURLStr = (http.allHeaderFields["X-Goog-Upload-URL"] ?? http.allHeaderFields["x-goog-upload-url"]) as? String
    guard let uploadURLStr, let uploadURL = URL(string: uploadURLStr) else { throw GError.badResp }

    // 2) Upload bytes + finalize
    var put = URLRequest(url: uploadURL)
    put.httpMethod = "POST"
    put.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
    put.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
    put.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
    put.httpBody = data

    let (finalData, finalResp) = try await URLSession.shared.data(for: put)
    guard let finalHTTP = finalResp as? HTTPURLResponse, (200..<300).contains(finalHTTP.statusCode) else {
        let code = (finalResp as? HTTPURLResponse)?.statusCode ?? -1
        throw GError.badHTTP(code, String(data: finalData, encoding: .utf8) ?? "")
    }

    struct Uploaded: Decodable {
        struct F: Decodable {
            let uri: String
        }
        let file: F
    }
    let uploaded = try JSONDecoder().decode(Uploaded.self, from: finalData)
    return uploaded.file.uri
}
