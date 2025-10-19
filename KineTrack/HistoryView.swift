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
                    Text("\(recording.exerciseName ?? "N/A") at \(recording.timestamp?.formatted(date: .numeric, time: .omitted) ?? "N/A")")
                        .font(.headline)
                        .fontWeight(.regular)
                }
            }
            .navigationBarTitle("History")
        }
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
