//
//  WebSocketManager.swift
//  KineTrack
//
//  Created by Zeedan on 10/19/25.
//

import Foundation
import UIKit

class WebSocketManager: NSObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private let urlSession = URLSession(configuration: .default)

    func connect() {
        // Replace localhost with your actual server IP if needed
        guard let url = URL(string: "wss://kinetrack.onrender.com/ws/analyze") else {
            print("Invalid URL")
            return
        }
        
        webSocketTask = urlSession.webSocketTask(with: url)
        webSocketTask?.resume()
        print("Connected to WebSocket")
        
        listen()
    }

    func sendPing() {
        let message = URLSessionWebSocketTask.Message.string("ping")
        webSocketTask?.send(message) { error in
            if let error = error {
                print("Error sending message: \(error)")
            } else {
                print("Sent: ping")
            }
        }
    }
    
    func sendPoseFrame(poseName: String, frameID: Int, image: UIImage) {
        guard let base64 = image.toBase64JPEG(quality: 0.3) else {
            print("Failed to encode image")
            return
        }

        let payload: [String: Any] = [
            "type": "pose",
            "pose_name": poseName,
            "frame_id": frameID,
            "frame": base64
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            print("Failed to serialize payload")
            return
        }

        webSocketTask?.send(.string(jsonString)) { error in
            if let error = error {
                print("Error sending pose frame: \(error)")
            } else {
                print("Sent frame \(frameID) with pose \(poseName)")
            }
        }
    }

    
    private func listen() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .failure(let error):
                print("Receive error: \(error)")
            case .success(let message):
                switch message {
                case .string(let text):
                    print("Received text: \(text)")
                    
                    if let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let message = json["message"] as? String {
                        KineSpeaker.shared.speak(message)
                    }
                case .data(let data):
                    print("Received data")
                @unknown default:
                    print("Unknown message type received")
                }
            }
            // Keep listening for new messages
            self?.listen()
        }
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        print("Disconnected")
    }
}
