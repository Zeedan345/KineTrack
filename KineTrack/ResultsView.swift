//
//  ResultsView.swift
//  KineTrack
//
//  Created by Zeedan on 10/19/25.
//

import SwiftUI
import AVKit

struct ResultsView: View {
    let videoURL: URL
    let position: Position
    let feedback: String?
    
    @Environment(\.presentationMode) var presentationMode
    @State private var player: AVPlayer
    @State private var isPlaying: Bool = true
    
    init(videoURL: URL, position: Position, feedback: String?) {
        self.videoURL = videoURL
        self.position = position
        self.feedback = feedback
        _player = State(initialValue: AVPlayer(url: videoURL))
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Video player
            VideoPlayer(player: player)
                .aspectRatio(contentMode: .fit)
                .cornerRadius(12)
                .shadow(radius: 5)
                .onAppear { player.play() }
                .onDisappear { player.pause() }
            
            // Position name
            Text("Position: \(position.name)")
                .font(.title3.bold())
                .foregroundColor(.primary)
            
            // Feedback section
            if let feedback = feedback, !feedback.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Gemini Feedback")
                        .font(.headline)
                    ScrollView {
                        Text(.init(feedback))
                            .font(.body)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .frame(maxHeight: 200)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(UIColor.secondarySystemBackground)))
            } else {
                ProgressView("Awaiting Gemini feedback...")
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(UIColor.secondarySystemBackground)))
            }
            
            Spacer()
            
            // Controls
            HStack(spacing: 30) {
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .resizable()
                        .frame(width: 60, height: 60)
                        .foregroundColor(.blue)
                }
                
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text("Retake")
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 20)
                    .background(Color.red.opacity(0.9))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
        }
        .padding()
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }
}
