//
//  CameraView.swift
//  Heart Sensor
//  Created by Zeedan Feroz Khan on 6/3/25.


import SwiftUI
import AVFoundation
import CoreGraphics

struct CameraView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SubjectEntity.timestamp, ascending: true)],
        animation: .default)
    private var subjects: FetchedResults<SubjectEntity>

    @StateObject private var warningMessages = WarningMessage()
    @StateObject private var model: FrameHandler
    @State private var isShowingSubjectPicker = false
    @State private var selectedSubject: SubjectEntity?
    @State private var recordingDuration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var previewView = VideoPreviewView()
    @State private var showSettingsSheet = false
    @State private var isShowingOfflinePredView: Bool = false
    @State private var showErrorAlert: Bool = false

    @State private var selectedVideoURL: URL? = nil
    @State private var showVideoPicker: Bool = false
    @State private var savedOrientation: UIDeviceOrientation?
    @AppStorage("isCameraEnabled") private var isCameraEnabled: Bool = true
    @AppStorage("selectedMode") private var selectedMode:Int = 0
    
    @Environment(\.presentationMode) var presentationMode
    
    @State private var isLoadingVideo: Bool = false

    init(selectedSubject: SubjectEntity? = nil) {
        let warnings = WarningMessage()
        _warningMessages = StateObject(wrappedValue: warnings)
        _model = StateObject(wrappedValue: FrameHandler(
            warningMessages: warnings,
            selectedSubject: selectedSubject
        ))
        _selectedSubject = State(initialValue: selectedSubject)
    }

    var body: some View {
        NavigationView {
            ZStack {
                CameraPreview(session: model.captureSession, preview: $previewView)
                    .ignoresSafeArea(.all, edges: .all)
                BoundingBoxView(model: model,tracker: model.tracker, previewView: previewView)
                    .ignoresSafeArea(.all, edges: .all)

                // Warnings overlay
                VStack(spacing: 2) {
                    ForEach(warningMessages.warnings) { msg in
                        Text(msg.text)
                            .foregroundColor(msg.text == "Camera is unstable" ? .red : .yellow)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 6)
                            .cornerRadius(10)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .animation(.easeInOut, value: warningMessages.warnings)
                    }
                }
                .padding(.top, 25)
                .padding(.trailing, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                // Info & status (top-left)
                VStack(alignment: .leading, spacing: 2) {
                    if !model.resolution.isEmpty {
                        Text(model.resolution)
                            .foregroundColor(.white)
                            .font(.caption)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 6)
                            .padding(4)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                    }
                    if !model.frameRate.isEmpty {
                        Text(model.frameRate)
                            .foregroundColor(.white)
                            .font(.caption)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 6)
                            .padding(4)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                    }
                    let or = savedOrientation == nil ? model.orienatation : savedOrientation!
                    Text(or.isPortrait ? "Portrait mode" : "Landscape mode")
                        .foregroundColor(.white)
                        .font(.caption)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .padding(4)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                    if model.tracker.detections.count != 0 && isCameraEnabled {
                        Text("\(model.tracker.detections.count) QR Codes Detected")
                            .foregroundColor(.red)
                            .font(.system(.headline, design: .monospaced))
                            .padding(.vertical, 2)
                            .padding(.horizontal, 6)
                            .padding(4)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                    }
                    if model.isRecording && isCameraEnabled {
                        Text(formatDuration(recordingDuration))
                            .foregroundColor(.red)
                            .font(.system(.title2, design: .monospaced))
                            .fontWeight(.bold)
                            .padding(6)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(4)
                    }
                    if model.isDepthDataAvailable {
                        if let depth = model.depthInMeter {
                            if depth < 0.05 {
                                Text("Move Camera Away From The Subject")
                                    .foregroundColor(.red)
                                    .font(.system(.headline, design: .monospaced))
                                    .padding(.vertical, 2)
                                    .padding(.horizontal, 6)
                                    .padding(4)
                                    .background(Color.black.opacity(0.7))
                                    .cornerRadius(4)
                            }
                        }
                    } else {
                        Text("Depth sensor unavailable - maintain 50cm+ distance")
                            .foregroundColor(.orange)
                            .font(.system(.caption, design: .monospaced))
                            .padding(.vertical, 2)
                            .padding(.horizontal, 6)
                            .padding(4)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                    }
                }
                .padding(.top, 25)
                .padding(.leading, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                
                VStack(alignment: .center) {
                    
                }
                    

                // Record & controls (bottom)
                VStack {
                    Spacer()
                    ZStack {
                        if !model.isRecording{
                            HStack() {
                                HStack {
                                    Button {
                                        if selectedSubject == nil {
                                            if subjects.isEmpty { showErrorAlert = true }
                                            else {
                                                selectedSubject = subjects.first
                                                isShowingSubjectPicker = true
                                            }
                                        } else {
                                            showVideoPicker = true
                                        }
                                    } label: {
                                        Image(systemName: "film")
                                            .resizable().frame(width: 26, height: 26)
                                            .foregroundColor(.white)
                                    }
                                    .padding()
                                    Button {
                                        isShowingSubjectPicker.toggle()
                                    } label: {
                                        Image(systemName: "person.badge.plus.fill")
                                            .resizable().frame(width: 26, height: 26)
                                            .foregroundColor(.white)
                                    }
                                    .padding()
                                }
                                Spacer()
                                // Offline video picker
                                HStack {
                                    Button {
                                        if model.cameraPosition == .back {
                                            model.cameraPosition = .front
                                        } else {
                                            model.cameraPosition = .back
                                        }
                                        model.checkPermission()
                                    } label: {
                                        Image(systemName: "goforward")
                                            .resizable().frame(width: 26, height: 26)
                                            .foregroundColor(.white)
                                    }
                                    .padding()
                                }
                            }
                        }
                        // Record/stop button
                        Button {
                            guard isCameraEnabled else { return }
                            if model.isRecording {
                                model.stopRecording()
                                stopTimer()
                                if model.tracker.state == .offline {
                                    isShowingOfflinePredView = true
                                }
                            } else {
                                if selectedSubject == nil {
                                    if subjects.isEmpty {
                                        showErrorAlert = true
                                    } else {
                                        selectedSubject = subjects.first
                                        isShowingSubjectPicker = true
                                    }
                                } else {
                                    model.startRecording()
                                    savedOrientation = model.orienatation
                                    startTimer()
                                }
                            }
                        } label: {
                            Image(systemName: model.isRecording ? "stop.circle.fill" : "record.circle")
                                .resizable().frame(width: 60, height: 60)
                                .foregroundColor(isCameraEnabled ? (model.isRecording ? .red : .white) : .gray)
                                .padding()
                                .shadow(color: .black.opacity(0.2), radius: 12)
                                .padding().shadow(radius: 12)
                        }
                        .disabled(!isCameraEnabled)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 25)
                }
                if isLoadingVideo {
                    ZStack {
                        Color.black.opacity(0.7)
                            .ignoresSafeArea()
                        
                        VStack {
                            ProgressView("Processing video...")
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                                .foregroundColor(.white)
                            
                            Text("This may take a moment")
                                .foregroundColor(.white)
                                .padding(.top, 20)
                        }
                    }
                }
                // NavigationLinks for offline/results
                NavigationLink(isActive: $isShowingOfflinePredView) {
                    if let url = model.videoURL, let subj = selectedSubject {
                        OfflinePredictionView(url: url, selectedSubject: subj, warningMessages: model.warningMessages, savedOrientation: savedOrientation)
                            .navigationTitle("Offline View")
                            .navigationBarBackButtonHidden(true)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarLeading) {
                                    Button(action: {
                                        presentationMode.wrappedValue.dismiss()
                                        model.videoURL = nil
                                    }) {
                                        HStack {
                                            Image(systemName: "chevron.left")
                                            Text("Back")
                                        }
                                    }
                                }
                            }
                    } else { EmptyView() }
                } label: { EmptyView() }
                NavigationLink(
                    isActive: Binding(
                        get: { selectedVideoURL != nil },
                        set: { if !$0 { selectedVideoURL = nil } }
                    )
                ) {
                    if let url = selectedVideoURL, let subj = selectedSubject {
                        OfflinePredictionView(url: url, selectedSubject: subj, warningMessages: model.warningMessages, savedOrientation: .portrait)
                            .navigationTitle("Offline View")
                            .navigationBarBackButtonHidden(true)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarLeading) {
                                    Button(action: {
                                        presentationMode.wrappedValue.dismiss()
                                        selectedVideoURL = nil
                                    }) {
                                        HStack {
                                            Image(systemName: "chevron.left")
                                            Text("Back")
                                        }
                                    }
                                }
                            }
                    } else { EmptyView() }
                } label: { EmptyView() }

            }
            .onAppear {
                model.setViewContext(viewContext)
                model.startSession()
            }
            .onDisappear {
                model.stopSession()
            }
            .onChange(of: model.selectedResolution) { newRes in
                model.customApplyFormat()
            }
            .onChange(of: model.selectedFrameRate) { newFrame in
                model.customApplyFormat()
            }
            .onChange(of: isShowingOfflinePredView) { newValue in
                if newValue == false {
                    savedOrientation = nil
                }
            }
            .onChange(of: model.isMotionDetectionEnabled) { newMessages in
                if model.isMotionDetectionEnabled {
                    model.startMonitoringMotion()
                } else {
                    model.stopMonitoringMotion()
                }
            }
            .onChange(of: selectedMode) { newMode in
                if newMode == 0 {
                    model.tracker.state = .offline
                } else if newMode == 1 {
                    model.tracker.state = .detecting
                }
            }
            .alert("No Subjects Exist", isPresented: $showErrorAlert) {
                Button("OK") { showErrorAlert = false }
            } message: {
                Text("Please add a new subject in the subjects tab")
            }
            // Subject picker
            .sheet(isPresented: $isShowingSubjectPicker) {
                NavigationView {
                    Form {
                        Picker(selection: $selectedSubject, label: Text("Subjects")) {
                            ForEach(subjects, id: \.self) { subject in
                                Text(subject.name ?? "Unnamed").tag(subject as SubjectEntity?)
                            }
                        }
                        .pickerStyle(WheelPickerStyle()).labelsHidden()
                    }
                    .navigationTitle(Text("Select a Subject"))
                    .toolbar {
                        ToolbarItemGroup(placement: .navigationBarTrailing) {
                            Button("Select") {
                                if let subj = selectedSubject {
                                    model.selectedSubject = subj
                                    isShowingSubjectPicker = false
                                }
                            }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            // Video picker
            .sheet(isPresented: $showVideoPicker) {
                VideoPicker(videoURL: $selectedVideoURL, isLoading: $isLoadingVideo)
            }
        }
    }

    private func startTimer() {
        recordingDuration = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingDuration += 0.1
        }
    }
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        recordingDuration = 0
    }
    //covert duration to min, sec, and milli sec
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
        let milliseconds = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%01d", minutes, seconds, milliseconds)
    }
}
