//
//  GeminiAPIFunctions.swift
//  KineTrack
//
//  Created by Zeedan on 10/19/25.
//

import Foundation

func sendPromptWithVideo(position: String, videoURL: URL, completion: @escaping (Result<Data, Error>) -> Void) {
    guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String else { return }
    let prompt = "You are a physical therapy assistant analyzing form from video. Focus on posture (spine neutrality, scapular control, knee valgus/varus, hip shift). Use the provided metadata JSON for rep boundaries, angles, and set context.Respond ONLY with JSON matching the response schema."
    let url = URL(string: "https://api.gemini.com/v1/responses")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    
    let boundary = "Boundary-\(UUID().uuidString)"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    
    var data = Data()
    
    // Add prompt
    data.append("--\(boundary)\r\n".data(using: .utf8)!)
    data.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
    data.append("\(prompt)\r\n".data(using: .utf8)!)
    
    // Add video
    let filename = videoURL.lastPathComponent
    let mimetype = "video/mp4" // adjust if needed
    if let videoData = try? Data(contentsOf: videoURL) {
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: \(mimetype)\r\n\r\n".data(using: .utf8)!)
        data.append(videoData)
        data.append("\r\n".data(using: .utf8)!)
    }
    
    data.append("--\(boundary)--\r\n".data(using: .utf8)!)
    
    // Send request
    let task = URLSession.shared.uploadTask(with: request, from: data) { responseData, _, error in
        if let error = error {
            completion(.failure(error))
        } else if let responseData = responseData {
            completion(.success(responseData))
        }
    }
    
    task.resume()
}
