import Foundation
import AVFoundation

// MARK: - KineSpeaker (fire-and-forget speak)
final class KineSpeaker {
    static let shared = KineSpeaker()

    // ⚙️ Configure this once (or expose a setter if you want to change voices at runtime)
    private let voiceID = "EXAVITQu4vr4xnSDxMaL" // <- replace with your voice id
    private let modelID = "eleven_flash_v2_5"
    private let outputFormat = "mp3_44100_128"

    private let apiKey: String
    private var player: AVAudioPlayer? // keep strong ref

    private init() {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "ELEVENLABS_API_KEY") as? String,
              !key.isEmpty else {
            fatalError("Missing ELEVENLABS_API_KEY in Info.plist")
        }
        self.apiKey = key
    }

    /// Call this to immediately speak your prompt.
    func speak(_ text: String) {
        Task {
            do {
                let data = try await synthesize(text: text)
                try await play(data: data)
            } catch {
                #if DEBUG
                print("KineSpeaker error:", error)
                #endif
            }
        }
    }

    // MARK: - Networking

    private struct VoiceSettings: Codable {
        let stability: Double
        let similarity_boost: Double
        let style: Double
        let use_speaker_boost: Bool
    }

    private struct TTSBody: Codable {
        let text: String
        let model_id: String
        let voice_settings: VoiceSettings
    }

    private func synthesize(text: String) async throws -> Data {
        var comps = URLComponents(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)")!
        comps.queryItems = [URLQueryItem(name: "output_format", value: outputFormat)]

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let body = TTSBody(
            text: text,
            model_id: modelID,
            voice_settings: .init(stability: 0.5, similarity_boost: 0.8, style: 0.0, use_speaker_boost: true)
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw NSError(domain: "KineSpeaker", code: (resp as? HTTPURLResponse)?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: "TTS request failed"])
        }
        return data
    }

    // MARK: - Audio

    @MainActor
    private func play(data: Data) throws {
        // If something is already playing, stop it (optional)
        player?.stop()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true)

        let p = try AVAudioPlayer(data: data)
        p.prepareToPlay()
        self.player = p
        p.play()
    }
}
