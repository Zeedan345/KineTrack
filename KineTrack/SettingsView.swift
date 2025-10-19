//
//  SettingsView.swift
//  KineTrack
//
//  Created by Zeedan on 10/18/25.
//

import SwiftUI
import AVFoundation

struct SettingsView: View {

    @AppStorage("selectedResolution") private var selectedResolution = 0
    @AppStorage("selectedFrameRate") private var selectedFrameRate = 0
    @State private var options: [CameraFormatOption] = []

    private let resolutionLabels = ["1280x720", "1920x1080", "3840x2160"]
    
    private var filteredOptions: [CameraFormatOption] {
        options.filter { resolutionLabels.contains($0.resolutionLabel) }
    }
    
    private var currentWidth: Int {
        selectedResolution / 10000
    }
    
    private var currentHeight: Int {
        selectedResolution % 10000
    }
    
    private var selectedOption: CameraFormatOption? {
        options.first { option in
            Int(option.width) == currentWidth && Int(option.height) == currentHeight
        }
    }
    
    private var availableFrameRates: [Int] {
        guard let option = selectedOption, !option.frameRates.isEmpty else {
            return []
        }
        let allowedRates = [24, 30, 60]
        return option.frameRates.filter { allowedRates.contains($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Video Settings")) {
                    if !options.isEmpty {
                        Picker("Video Resolution", selection: $selectedResolution) {
                            ForEach(filteredOptions) { option in
                                let tagValue = Int(option.width * 10000 + option.height)
                                Text(option.resolutionLabel)
                                    .tag(tagValue)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    if !availableFrameRates.isEmpty {
                        Picker("Frame Rate", selection: $selectedFrameRate) {
                            ForEach(availableFrameRates, id: \.self) { rate in
                                Text("\(rate) fps").tag(rate)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                setupInitialOptions()
            }
        }
    }
    
    private func setupInitialOptions() {
        options = discoverSupportedFormats(position: .back)
        
        //check if matching option
        let hasMatchingOption = options.contains { option in
            let optionResolution = Int(option.width * 10000 + option.height)
            return optionResolution == selectedResolution
        }
        
        //if not choose first one
        if !hasMatchingOption {
            if let firstOption = options.first {
                selectedResolution = Int(firstOption.width * 10000 + firstOption.height)
            } else {
                selectedResolution = 0
            }
        }
    }
}

