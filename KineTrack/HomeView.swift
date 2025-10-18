//
//  HomeView.swift
//  Heart Sensor
//
//  Created by Zeedan Feroz Khan on 6/3/25.
//

import SwiftUI

struct HomeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    
    @Binding var selectedTab: Int
    @AppStorage("syncEnabled") private var syncEnabled = true
    @State private var showProfileSheet = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Welcome Title
                    Text("Welcome to KineTrack")
                        .font(.largeTitle)
                        .padding(.top, 24)
                    Text("KineTrack helps you better your form and get more fit")

                    // Start Recording Card
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Start a New Recording")
                            .font(.headline)

                        Button(action: {
                            selectedTab = 2
                        }) {
                            HStack {
                                Image(systemName: "record.circle.fill")
                                Text("New Workout")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(UIColor.secondarySystemBackground)))

                    // Recent Sessions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Sessions")
                            .font(.headline)
                        
                        if true {
                            Text("No recordings yet.")
                                .foregroundColor(.gray)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 8) {
//                                    ForEach(allRecordings.prefix(20)) { recording in
//                                        RecentRecordingsView(recording: recording)
//                                    }
                                }
                            }
                            .frame(height: 200)
                        }
                    }
                   .padding()
                   .background(RoundedRectangle(cornerRadius: 16).fill(Color(UIColor.secondarySystemBackground)))
                    
                }
                .padding(.horizontal)
            }
            .navigationTitle("Dashboard")
        }
    }
}
