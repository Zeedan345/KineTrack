//
//  HistoryView.swift
//  KineTrack
//
//  Created by Zeedan on 10/18/25.
//

import SwiftUI
import AVKit

struct HistoryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.presentationMode) private var presentationMode
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \RecordingEntity.timestamp, ascending: false)],
        animation: .default)
    private var fetchedRecordings: FetchedResults<RecordingEntity>

    var body: some View {
        NavigationView {
            List(fetchedRecordings, id: \.self) { recording in
                NavigationLink(destination: RecordingView(recording: recording)) {
                    VStack(alignment: .leading) {
                        Text("\(recording.exerciseName ?? "N/A") at \(recording.timestamp?.formatted(date: .numeric, time: .omitted) ?? "N/A")")
                            .font(.headline)
                            .fontWeight(.regular)
                        Text("Recording ID: \(shortenedUUID(recording.recordingId))")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Text("Gemini Feedback")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(6)
                    }
                }
            }
            .navigationBarTitle("History")
        }
    }
    private func shortenedUUID(_ id: UUID?) -> String {
        guard let id = id else { return "" }
        let uuidString = id.uuidString
        // Show only the last 6 characters
        let shortPart = uuidString.suffix(6)
        return "…\(shortPart)"
    }

}

struct RecordingView: View {
    let recording: RecordingEntity
    
    var body: some View {
        VStack(spacing: 20) {
            if let url = getVideoURL() {
                VideoPlayer(player: AVPlayer(url: url))
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(12)
                    .shadow(radius: 8)
                    .frame(maxHeight: 300)
            } else {
                Text("No video available")
                    .foregroundColor(.secondary)
            }
            
            if let timestamp = recording.timestamp {
                Text(timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
            }
            if let feedback = recording.feedback, !feedback.isEmpty {
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
                ProgressView("Gemini feedback not available")
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(UIColor.secondarySystemBackground)))
            }
            Spacer()
        }
        .padding()
        .navigationTitle(recording.exerciseName ?? "Recording")
    }
    
    private func getVideoURL() -> URL? {
        if let path = recording.url {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}
