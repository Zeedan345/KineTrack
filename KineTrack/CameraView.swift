import SwiftUI
import AVFoundation
import CoreGraphics

struct CameraView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var model: FrameHandler
    @State private var previewView = VideoPreviewView()
    
    init() {
        _model = StateObject(wrappedValue: FrameHandler())
    }
    
    @Environment(\.presentationMode) var presentationMode
    @AppStorage("isCameraEnabled") private var isCameraEnabled: Bool = true
    
    @State private var isLoadingVideo: Bool = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var timer: Timer? = nil
    
    @State private var showVideoPicker: Bool = false
    @State private var selectedVideoURL: URL? = nil
    
    // Position-related state
    @State private var selectedPosition: Position? = nil
    @State private var isShowingPositionPicker: Bool = false
    @State private var showErrorAlert: Bool = false
    @State private var savedOrientation: AVCaptureVideoOrientation? = nil
    
    @State private var showResults: Bool = false
    

    var body: some View {
        NavigationView {
            ZStack {
                CameraPreview(session: model.captureSession, preview: $previewView)
                    .ignoresSafeArea(.all, edges: .all)

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
                    
                    // Show selected position
                    if let position = selectedPosition {
                        HStack(spacing: 4) {
                            Image(systemName: position.icon)
                            Text(position.name)
                        }
                        .foregroundColor(.white)
                        .font(.caption)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .padding(4)
                        .background(Color.blue.opacity(0.7))
                        .cornerRadius(4)
                    }
                }
                .padding(.top, 25)
                .padding(.leading, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // Record & controls (bottom)
                VStack {
                    Spacer()
                    ZStack {
                        if !model.isRecording {
                            HStack() {
                                HStack {
//                                    Button {
//                                        if selectedPosition == nil {
//                                            showErrorAlert = true
//                                        } else {
//                                            showVideoPicker = true
//                                        }
//                                    } label: {
//                                        Image(systemName: "film")
//                                            .resizable().frame(width: 26, height: 26)
//                                            .foregroundColor(.white)
//                                    }
//                                    .padding()
                                    
                                    Button {
                                        isShowingPositionPicker.toggle()
                                    } label: {
                                        Image(systemName: selectedPosition == nil ? "list.bullet.circle" : "list.bullet.circle.fill")
                                            .resizable().frame(width: 26, height: 26)
                                            .foregroundColor(selectedPosition == nil ? .white : .blue)
                                    }
                                    .padding()
                                }
                                Spacer()
                                
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
                                showResults = true
                                stopTimer()
                            } else {
                                if selectedPosition == nil {
                                    showErrorAlert = true
                                } else {
                                    model.startRecording(for: selectedPosition!)
                                    //savedOrientation = model.orienatation
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
                NavigationLink(isActive: $showResults) {
                    if let url = model.videoURL, let pos = selectedPosition {
                        ResultsView(model: model, videoURL: url, position: pos, feedback: model.aiFeedback)
                            .id(url)
                            .navigationBarBackButtonHidden(true)
                    } else {
                        EmptyView()
                    }
                } label: { EmptyView() }
            }
            .onAppear {
                model.setViewContext(viewContext)
                model.startSession()
                
                let socket = WebSocketManager()
                model.webSocketController = socket
                model.webSocketController?.connect()

                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    model.webSocketController!.sendPing()
                }

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
            .onChange(of: selectedPosition) { newPosition in
                model.selectedPosition = newPosition
            }
            // Position Picker Sheet
            .sheet(isPresented: $isShowingPositionPicker) {
                NavigationView {
                    PositionPickerView(selectedPosition: $selectedPosition)
                        .navigationTitle("Select Position")
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    isShowingPositionPicker = false
                                }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
            // Video picker
            .sheet(isPresented: $showVideoPicker) {
                VideoPicker(videoURL: $selectedVideoURL, isLoading: $isLoadingVideo)
            }
            // Error alert
            .alert("No Position Selected", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
                Button("Select Position") {
                    isShowingPositionPicker = true
                }
            } message: {
                Text("Please select a position before recording or uploading a video.")
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
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
        let milliseconds = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%01d", minutes, seconds, milliseconds)
    }
}
