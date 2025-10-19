//
//  ViewController.swift
//  KineTrack
//
//  Created by Zeedan on 10/18/25.
//

import Foundation
import UIKit

class ViewController: UIViewController, URLSessionWebSocketDelegate {
    
    private var webSocket: URLSessionWebSocketTask?
    var isConnected = false
    
    // Callback for received text messages
    var onTextReceived: ((String) -> Void)?
        
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        connect(urlString: "wss://kinetrack.onrender.com/ws/analyze")
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        connect(urlString: "wss://kinetrack.onrender.com/ws/analyze")
    }
    func connect(urlString: String) {
        guard let url = URL(string: urlString) else {
            print("Invalid URL")
            return
        }
        
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()
        
        receiveMessage()
        
        print("WebSocket connecting...")
    }
    
    func disconnect() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        isConnected = false
        print("WebSocket disconnected")
    }
    
    func sendData(_ data: Data) {
        let message = URLSessionWebSocketTask.Message.data(data)
        
        webSocket?.send(message) { error in
            if let error = error {
                print("WebSocket send error: \(error)")
            }
        }
    }
    
    func sendText(_ text: String) {
        let message = URLSessionWebSocketTask.Message.string(text)
        
        webSocket?.send(message) { error in
            if let error = error {
                print("WebSocket send error: \(error)")
            }
        }
    }
    
    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.onTextReceived?(text)
                case .data(let data):
                    print("Received data: \(data.count) bytes")
                @unknown default:
                    break
                }
                
                // Continue listening for messages
                self?.receiveMessage()
                
            case .failure(let error):
                print("WebSocket receive error: \(error)")
            }
        }
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        isConnected = true
        print("WebSocket connected")
        let startMessage: [String: Any] = [
            "type": "start",
            "exercise": "pushups"
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: startMessage),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            sendText(jsonString)
        }
        startPinging()
    }
    func startPinging() {
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] timer in
            guard let self = self, self.isConnected else {
                timer.invalidate()
                return
            }

            let pingMessage: [String: Any] = ["type": "ping"]
            if let jsonData = try? JSONSerialization.data(withJSONObject: pingMessage),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                self.sendText(jsonString)
                print("Ping sent")
            }
        }
    }

    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        isConnected = false
        print("WebSocket disconnected with code: \(closeCode)")
    }
}
