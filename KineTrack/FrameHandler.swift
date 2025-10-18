//
//  FrameHandler.swift
//
//  Created by Zeedan Feroz Khan
//

import AVFoundation
import SwiftUI
import CoreData
internal import Combine

//struct for camera format's
struct CameraFormatOption: Identifiable, Equatable {
    let id = UUID()
    let format: AVCaptureDevice.Format
    let width: Int32
    let height: Int32
    let frameRates: [Int]

    var resolutionLabel: String {
        switch (width, height) {
        case (3840, 2160): return "4K"
        case (1920, 1080): return "1080p HD"
        case (1280, 720):  return "720p HD"
        default:            return "\(width)x\(height)"
        }
    }
}

class FrameHandler: NSObject,
    ObservableObject,
    AVCaptureVideoDataOutputSampleBufferDelegate,
                    AVCaptureFileOutputRecordingDelegate, AVCaptureDepthDataOutputDelegate
{
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
    var isRecording: Bool = false
    
    @Published var resolution         = ""
    @Published var frameRate          = ""
    @Published var videoURL: URL?
    
    // Selected format & FPS state used by UI and configuration
    @Published var supportedFormats: [CameraFormatOption] = []
    @Published var selectedFormat: CameraFormatOption?
    @Published var selectedFPS: Int = 30

    @Published var cameraPosition    : AVCaptureDevice.Position = .back
    @AppStorage("selectedResolution") var selectedResolution = 0
    @AppStorage("selectedFrameRate") var selectedFrameRate = 0

    @Published var videoDimensions: CGSize?
    private var permissionGranted = false

    @Published var orienatation: UIDeviceOrientation = .portrait

    //TODO: Make Choosen Position
    override init() {
        super.init()
        checkPermission()
    }

    func setViewContext(_ context: NSManagedObjectContext) {
        self.viewContext = context
    }

    //Permission & Session
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
    func startRecording() {
        guard let movieOut = movieFileOutput, !movieOut.isRecording else { return }
        startTime     = Date()
        // Now begin recording on whatever lens is currently active
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture_\(UUID().uuidString).mov")
        sessionQueue.async {
            movieOut.startRecording(to: tmpURL, recordingDelegate: self)
            DispatchQueue.main.async { self.isRecording = true }
        }
    }

    func stopRecording() {
        guard let movieOut = movieFileOutput, movieOut.isRecording else { return }
        movieOut.stopRecording()
        DispatchQueue.main.async {
            self.isRecording         = false
            self.startTime           = nil
        }
    }

    //Setup Formats & Selection
    private func setupCaptureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .inputPriority
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        captureSession.outputs.forEach{ captureSession.removeOutput($0) }

        
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
        videoOut.setSampleBufferDelegate(self,
                                         queue: DispatchQueue(label: "sampleBufferQueue"))
        if captureSession.canAddOutput(videoOut) {
            captureSession.addOutput(videoOut)
            videoDataOutput = videoOut
        }

        let movieOut = AVCaptureMovieFileOutput()
        if captureSession.canAddOutput(movieOut) {
            captureSession.addOutput(movieOut)
            movieFileOutput = movieOut
        }
        let depthDataOutput = AVCaptureDepthDataOutput()
        depthDataOutput.isFilteringEnabled = true
        if captureSession.canAddOutput(depthDataOutput) {
            captureSession.addOutput(depthDataOutput)
            depthDataOutput.setDelegate(self, callbackQueue: DispatchQueue(label: "depthQueue"))
        }
        if let connection = depthDataOutput.connection(with: .depthData) {
            connection.isEnabled = true
        }
        captureSession.commitConfiguration()
        customApplyFormat()
    }
    
    //get the settings set and apply those
    func customApplyFormat() {
        let sorted = discoverSupportedFormats(position: cameraPosition)
        if selectedResolution == 0  {
            DispatchQueue.main.async {
                if let top = sorted.first {
                    self.selectedFormat = top
                    self.selectedResolution = Int(top.width * 10000 + top.height)
                    self.selectedFPS = top.frameRates.max() ?? self.selectedFPS
                    self.selectedFrameRate = self.selectedFPS
                }
                self.supportedFormats = sorted
                self.applyCameraSettings(format: self.selectedFormat!,
                                         fps:    self.selectedFPS)
            }
        } else {
            let width = self.selectedResolution / 10000
            let height = self.selectedResolution % 10000
            if let selectedOption = sorted.first(where: { Int($0.width) == width && Int($0.height) == height }) {
                DispatchQueue.main.async {
                    self.selectedFormat = selectedOption
                    self.selectedFPS = Int(self.selectedFrameRate)
                    self.supportedFormats = sorted
                    self.applyCameraSettings(format: self.selectedFormat!,
                                             fps:    self.selectedFPS)
                }
            }
        }
        //update the UI
        updateCurrentSettingsOnMain()
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
                self.selectedFPS    = fps
                self.updateCurrentSettingsOnMain()
            }
        }
    }

    //these variables are used in the UI of camera
    private func updateCurrentSettingsOnMain() {
        DispatchQueue.main.async {
            guard let fmt = self.selectedFormat else {
                print("Format Empty")
                return
            }
            self.resolution      = fmt.resolutionLabel
            self.frameRate       = "\(self.selectedFPS) FPS"
            self.videoDimensions = CGSize(width: CGFloat(fmt.width),
                                          height: CGFloat(fmt.height))
        }
    }

    //Callbacks & Recording
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from _: [AVCaptureConnection],
                    error: (any Error)?) {
        DispatchQueue.main.async {
            self.isRecording = false
            self.videoURL    = outputFileURL
        }
        if let e = error { print("Recording Error: \(e)") }
    }
    
    //encrypt and save local
//    private func saveLocal(subject: SubjectEntity, fileURL: URL, duration: Double) -> RecordingEntity? {
//        guard let viewContext = self.viewContext else { return nil }
//        guard let uid = Auth.auth().currentUser?.uid else { return nil }
//        
//        do {
//            //admin is key so only they can access
//            let rawData = try Data(contentsOf: fileURL)
//            
//            let newRecording = RecordingEntity(context: viewContext)
//            newRecording.recordingId = UUID()
//            newRecording.timestamp = Date()
//            if let startTime = self.startTime {
//                let warn = warningMessages.warningHistory.map {
//                    "\($0.timestamp.timeIntervalSince1970 - startTime.timeIntervalSince1970): \($0.text)"
//                }
//                newRecording.warnings = warn
//            }
//            newRecording.orientation = savedOrientation.isPortrait ? "portrait" : "landscape"
//            newRecording.duration = duration
//            newRecording.synced = synced
//            newRecording.ownerId = uid
//            
//            try? viewContext.save()
//            return newRecording
//        } catch {
//            print("Error while encrypting\(error)")
//            return nil
//        }
//    }
    
    //buffer to capture the actual video
    func captureOutput(
      _ output: AVCaptureOutput,
      didOutput sampleBuffer: CMSampleBuffer,
      from connection: AVCaptureConnection ) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    }
}

