//  ContentView.swift
//  Heart Sensor
//


import SwiftUI
import CoreData
import UIKit

struct ContentView: View {
    // Use this to change the current tab
    @State private var selectedTab = 0
    @Environment(\.managedObjectContext) private var viewContext

    // Hold the selected subject for CameraView
//    @State private var cameraSubject: SubjectEntity? = nil

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab)
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Home")
                }
                .tag(0)

//            SubjectsView()
//                .tabItem {
//                    Image(systemName: "person")
//                    Text("Subjects")
//                }
//                .tag(1)

            CameraView()
                .tabItem {
                    Image(systemName: "camera")
                    Text("Camera")
                }
                .tag(2)

            HistoryView()
                .tabItem {
                    Image(systemName: "book.pages")
                    Text("History")
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
                .tag(4)
        }
        .onAppear {
            customTabAppearence()
        }
        .onChange(of: selectedTab) { _ in
            customTabAppearence()
        }
        // Listen for programmatic camera navigation
//        .onReceive(NotificationCenter.default.publisher(for: .goToCameraTab)) { notification in
//            if let subject = notification.object as? SubjectEntity {
//                cameraSubject = subject
//                selectedTab = 2
//            }
//        }
    }

    //this is for camera view
    private func customTabAppearence() {
        if selectedTab == 2 {
            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = UIColor.black.withAlphaComponent(0.05)
            appearance.stackedLayoutAppearance.normal.iconColor = UIColor.white.withAlphaComponent(0.7)
            appearance.stackedLayoutAppearance.selected.iconColor = UIColor.white
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.white.withAlphaComponent(0.7)]
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.white]
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        } else {
            UITabBar.appearance().standardAppearance = UITabBarAppearance()
            UITabBar.appearance().scrollEdgeAppearance = UITabBarAppearance()
        }
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}
