//
//  FrameHandler.swift
//
//  Created by Zeedan Feroz Khan
//

import AVFoundation
import SwiftUI
import CoreData
internal import Combine

struct CameraFormatOption: Identifiable, Equatable {
    let id = UUID()
    let format: AVCaptureDevice.Format
    let width: Int32
    let height: Int32
    let frameRates: [Int]

    var resolutionLabel: String {
        switch (width, height) {
        case (3840, 2160): return "3840x2160"
        case (1920, 1080): return "1920x1080"
        case (1280, 720):  return "1280x720"
        default:            return "\(width)x\(height)"
        }
    }
}

class FrameHandler: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureFileOutputRecordingDelegate {
    
    // Core session & device I/O
    private var viewContext: NSManagedObjectContext?
    private(set) var captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "sessionQueue")
    private var videoDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private var movieFileOutput: AVCaptureMovieFileOutput?
    private let ciContext = CIContext()
    private var startTime: Date? = nil
    @Published var isRecording = false
    
    @Published var resolution = ""
    @Published var frameRate = ""
    @Published var videoURL: URL?
    
    // Position tracking
    @Published var selectedPosition: Position?
    @Published var currentRecordingPosition: Position?
    
    // Selected format & FPS state used by UI and configuration
    @Published var supportedFormats: [CameraFormatOption] = []
    @Published var selectedFormat: CameraFormatOption?
    @Published var selectedFPS: Int = 30

    @Published var cameraPosition: AVCaptureDevice.Position = .back
    @AppStorage("selectedResolution") var selectedResolution = 0
    @AppStorage("selectedFrameRate") var selectedFrameRate = 0

    @Published var videoDimensions: CGSize?
    private var permissionGranted = false
    
    var webSocketController: WebSocketManager?
    private var frameCount: Int = 0

    
    @Published var orienatation: UIDeviceOrientation = .portrait
    @Published var aiFeedback: String?

    override init() {
        super.init()
        checkPermission()
    }

    func setViewContext(_ context: NSManagedObjectContext) {
        self.viewContext = context
    }

    // Permission & Session
    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
            sessionQueue.async { self.setupCaptureSession() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                self?.permissionGranted = granted
                if granted { self?.sessionQueue.async { self?.setupCaptureSession() } }
            }
        default:
            permissionGranted = false
        }
    }

    func startSession() {
        sessionQueue.async { self.captureSession.startRunning() }
    }

    func stopSession() {
        sessionQueue.async { self.captureSession.stopRunning() }
    }

    // Recording Control
    func startRecording(for position: Position) {
        guard let movieOut = movieFileOutput, !movieOut.isRecording else { return }
        frameCount = 0
        startTime = Date()
        currentRecordingPosition = position
        
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture_\(UUID().uuidString).mov")
        
        DispatchQueue.main.async {
            self.isRecording = true
            print("Started recording for position")
        }
        sessionQueue.async {
            movieOut.startRecording(to: tmpURL, recordingDelegate: self)
        }
    }

    func stopRecording() {
        guard let movieOut = movieFileOutput, movieOut.isRecording else { return }
        frameCount = 0
        movieOut.stopRecording()
        DispatchQueue.main.async {
            self.isRecording = false
            self.startTime = nil
            print("Stopped recording for position")
        }
    }

    // Setup Formats & Selection
    private func setupCaptureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .inputPriority
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        captureSession.outputs.forEach { captureSession.removeOutput($0) }

        guard let device = findAvailableCamera(position: cameraPosition) else {
            print("Error: Unable to add video input")
            return
        }
        videoDevice = device
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                self.videoInput = input
            }
        } catch {
            print("Failed to create camera input: \(error)")
        }

        let videoOut = AVCaptureVideoDataOutput()
        videoOut.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sampleBufferQueue"))
        if captureSession.canAddOutput(videoOut) {
            captureSession.addOutput(videoOut)
            videoDataOutput = videoOut
        }

        let movieOut = AVCaptureMovieFileOutput()
        if captureSession.canAddOutput(movieOut) {
            captureSession.addOutput(movieOut)
            movieFileOutput = movieOut
        }
        captureSession.commitConfiguration()
        customApplyFormat()
    }
    
    // Get the settings set and apply those
    func customApplyFormat() {
        let sorted = discoverSupportedFormats(position: cameraPosition)
        if selectedResolution == 0 {
            DispatchQueue.main.async {
                if let top = sorted.first {
                    self.selectedFormat = top
                    self.selectedResolution = Int(top.width * 10000 + top.height)
                    self.selectedFPS = top.frameRates.max() ?? self.selectedFPS
                    self.selectedFrameRate = self.selectedFPS
                }
                self.supportedFormats = sorted
                if let format = self.selectedFormat {
                    self.applyCameraSettings(format: format, fps: self.selectedFPS)
                }
            }
        } else {
            let width = self.selectedResolution / 10000
            let height = self.selectedResolution % 10000
            if let selectedOption = sorted.first(where: { Int($0.width) == width && Int($0.height) == height }) {
                DispatchQueue.main.async {
                    self.selectedFormat = selectedOption
                    self.selectedFPS = Int(self.selectedFrameRate)
                    self.supportedFormats = sorted
                    self.applyCameraSettings(format: selectedOption, fps: self.selectedFPS)
                }
            }
        }
        updateCurrentSettingsOnMain()
    }
    
    // Discover supported formats
    private func discoverSupportedFormats(position: AVCaptureDevice.Position) -> [CameraFormatOption] {
        guard let device = findAvailableCamera(position: position) else { return [] }
        
        var formatOptions: [CameraFormatOption] = []
        for format in device.formats {
            let desc = format.formatDescription
            let dims = CMVideoFormatDescriptionGetDimensions(desc)
            let w = dims.width
            let h = dims.height
            
            let frameRates = format.videoSupportedFrameRateRanges.map { Int($0.maxFrameRate) }
            
            let option = CameraFormatOption(
                format: format,
                width: w,
                height: h,
                frameRates: frameRates
            )
            formatOptions.append(option)
        }
        
        // Sort by resolution descending
        return formatOptions.sorted { $0.width * $0.height > $1.width * $1.height }
    }

    // Apply Settings
    func applyCameraSettings(format: CameraFormatOption, fps: Int) {
        guard let device = videoDevice else { return }
        sessionQueue.async {
            try? device.lockForConfiguration()
            device.activeFormat = format.format
            
            let supportedRanges = format.format.videoSupportedFrameRateRanges
            let maxSupportedFPS = supportedRanges.map { $0.maxFrameRate }.min() ?? Double(fps)
            let clampedFPS = min(Double(fps), maxSupportedFPS)
            let d = CMTimeMake(value: 1, timescale: Int32(clampedFPS))
            device.activeVideoMinFrameDuration = d
            device.activeVideoMaxFrameDuration = d
            device.unlockForConfiguration()
            DispatchQueue.main.async {
                self.selectedFormat = format
                self.selectedFPS = fps
                self.updateCurrentSettingsOnMain()
            }
        }
    }

    // These variables are used in the UI of camera
    private func updateCurrentSettingsOnMain() {
        DispatchQueue.main.async {
            guard let fmt = self.selectedFormat else {
                print("Format Empty")
                return
            }
            self.resolution = fmt.resolutionLabel
            self.frameRate = "\(self.selectedFPS) FPS"
            self.videoDimensions = CGSize(width: CGFloat(fmt.width), height: CGFloat(fmt.height))
        }
    }
    func sendFrameToServer(frame: UIImage, pose: String, frameID: Int) {
        guard let socket = webSocketController else {
            print("WebSocket not connected")
            return
        }
        socket.sendPoseFrame(poseName: pose, frameID: frameID, image: frame)
    }


    // Callbacks & Recording
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from _: [AVCaptureConnection],
                    error: (any Error)?) {
        
        
        DispatchQueue.main.async {
            self.isRecording = false
            self.videoURL = outputFileURL
        
            print("Recording completed for position")
            print("Video saved at: \(outputFileURL)")
            
            if let position = self.currentRecordingPosition {
                sendPromptWithVideo(position: position.name, videoURL: outputFileURL) {result in
                    switch result {
                    case .success(let text):
                        self.aiFeedback = text
                        print("Response: \(text)")
                    case .failure(let error):
                        print("Error: \(error)")
                    }
                    self.saveRecordingWithPosition(url: outputFileURL, position: position)
                }
            }

        }
        
        if let e = error {
            print("Recording Error: \(e)")
        }
    }
    
    // Optional: Save recording with position metadata
    private func saveRecordingWithPosition(url: URL, position: Position) {
        guard let viewContext = self.viewContext else { return }
        
        let newRecording = RecordingEntity(context: viewContext)
        newRecording.recordingId = UUID()
        newRecording.timestamp = Date()
        newRecording.url = url.path
        newRecording.exerciseName = position.name
        
        try? viewContext.save()
    }
    
    // Buffer to capture the actual video
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        frameCount += 1
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage)
        
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.7) else { return }
        
        if frameCount % 15 == 0 && isRecording == true, let position = selectedPosition {
            let pos = position.name == "Squat" ? "squats" : "pushups"
            webSocketController?.sendPoseFrame(poseName: pos, frameID: frameCount, image: uiImage)
        }
    }
}
