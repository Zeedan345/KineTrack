//
//  FrameHandler.swift
//  ColorCalc
//
//  Created by Zeedan Feroz Khan on 5/25/25.
//

import AVFoundation
import SwiftUI
import CoreData
import FirebaseFirestore
import FirebaseStorage
import CryptoKit
import CoreMotion
import CoreML
import Vision
import FirebaseAuth

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

    //Published UI state
    @Published var isRecording        = false
    @Published var selectedSubject: SubjectEntity?
    @Published var supportedFormats   = [CameraFormatOption]()
    @Published var selectedFormat: CameraFormatOption?
    @Published var selectedFPS        = 30

    @Published var resolution         = ""
    @Published var frameRate          = ""
    @Published var videoURL: URL?
    @Published var qrCodesCount       = 0
    @Published var cameraPosition    : AVCaptureDevice.Position = .back

    // Warnings & QR
    @AppStorage("isMotionDetectionEnabled") var isMotionDetectionEnabled = true
    @AppStorage("isLowLightDetectionEnabled") private var isLowLightDetectionEnabled = true
    @AppStorage("selectedResolution") var selectedResolution = 0
    @AppStorage("selectedFrameRate") var selectedFrameRate = 0
    @AppStorage("selectedExposureMode") private var selectedExposureMode = true
    
    private let motionManager = CMMotionManager()
    private var isLowLightWarningShown = false
    private var isShakyWarningShown    = false
    let warningMessages: WarningMessage

    @Published var tracker         = QRTracker()
    @Published var videoDimensions: CGSize?
    private var permissionGranted = false

    var saveHistory: Bool = false
    @Published var startTime: Date?

    private var startTracking    = false
    private var desiredQrToTrack = 0
    
    @Published var depthInMeter: Float?
    @Published var isDepthDataAvailable = false
    @Published var orienatation: UIDeviceOrientation = .portrait

    init(warningMessages: WarningMessage, selectedSubject: SubjectEntity? = nil) {
        self.warningMessages = warningMessages
        self.selectedSubject = selectedSubject
        super.init()
        checkPermission()
    }
    
    //init for offline
    init(forOfflineProcessing: Bool, warningMessages: WarningMessage, selectedSubject: SubjectEntity) {
        self.warningMessages = warningMessages
        self.selectedSubject = selectedSubject
        super.init()
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
        if isMotionDetectionEnabled {
            startMonitoringMotion()
        }
    }

    func stopSession() {
        sessionQueue.async { self.captureSession.stopRunning() }
        stopMonitoringMotion()
    }

    // Recording Control
    func startRecording() {
        guard let movieOut = movieFileOutput, !movieOut.isRecording else { return }
        startTracking = true
        saveHistory   = true
        startTime     = Date()

        // Clear any old QR point
        DispatchQueue.main.async { self.tracker.trackedPoint = nil }
        fixISOAndShutter()
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
        unfixISOAndShutter()
        DispatchQueue.main.async {
            if (self.tracker.state == .tracking) {
                self.tracker.state       = .detecting
            }
            self.tracker.trackedPoint = nil
            self.isRecording         = false
            self.saveHistory         = false
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
        DispatchQueue.main.async {
            self.isDepthDataAvailable = self.checkDepthCapability()
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
    
    //check if saving local/cloud&local
    func saveEncryptedData(fileUrl: URL, accelPointsToSave: [AccelPoint], savedOrientation: UIDeviceOrientation, duration: Double, selectedQRCode: QRDetection) {
        guard let subject = selectedSubject else { return }
        if let recordingEntity = saveLocal(
            subject: subject,
            fileURL: fileUrl,
            cloudURL: nil,
            accelPointsToSave: accelPointsToSave,
            savedOrientation: savedOrientation,
            synced: false,
            duration: duration, selectedQRCode: selectedQRCode
        ) {
            let syncEnabled = UserDefaults.standard.bool(forKey: "syncEnabled")
            if syncEnabled {
                uploadEncryptedVideoToFirebase(
                    fileURL: fileUrl,
                    recordingEntity: recordingEntity,
                    accelPointsToSave: accelPointsToSave,
                    savedOrientation: savedOrientation,
                    duration: duration
                )
            }
        } else {
            print("Failed to save local recording entity.")
        }
    }
    
    //encrypt and save local
    private func saveLocal(subject: SubjectEntity, fileURL: URL, cloudURL: String?, accelPointsToSave: [AccelPoint], savedOrientation: UIDeviceOrientation, synced: Bool, duration: Double, selectedQRCode: QRDetection) -> RecordingEntity? {
        guard let viewContext = self.viewContext else { return nil }
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        
        do {
            //admin is key so only they can access
            let rawData = try Data(contentsOf: fileURL)
            guard let key = getOrCreateKey(for: "admin") else { return nil}
            let sealedBox = try AES.GCM.seal(rawData, using: key)
            let encryptedData = sealedBox.combined!
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let encryptedURL = docs.appendingPathComponent("enc_\(UUID().uuidString).mov")
            try encryptedData.write(to: encryptedURL)
            
            let newRecording = RecordingEntity(context: viewContext)
            newRecording.recordingId = UUID()
            newRecording.subject = subject
            newRecording.url = encryptedURL.path
            newRecording.cloudUrl = cloudURL
            newRecording.timestamp = Date()
            
            for point in accelPointsToSave {
                let accelEntity = AccelPointEntity(context: viewContext)
                accelEntity.time = point.time
                accelEntity.ax = point.ax
                accelEntity.ay = point.ay
                accelEntity.recording = newRecording
            }
            if let startTime = self.startTime {
                let warn = warningMessages.warningHistory.map {
                    "\($0.timestamp.timeIntervalSince1970 - startTime.timeIntervalSince1970): \($0.text)"
                }
                newRecording.warnings = warn
            }
            newRecording.orientation = savedOrientation.isPortrait ? "portrait" : "landscape"
            newRecording.duration = duration
            newRecording.synced = synced
            newRecording.ownerId = uid
            
            let qrcode = QREntity(context: viewContext)
            qrcode.x = selectedQRCode.boundingBox.midX
            qrcode.y = selectedQRCode.boundingBox.midY
            qrcode.width = selectedQRCode.boundingBox.width
            qrcode.height = selectedQRCode.boundingBox.height
            newRecording.qrcode = qrcode
            try? viewContext.save()
            return newRecording
        } catch {
            print("Error while encrypting\(error)")
            return nil
        }
    }

    //save cloud and downaload
    private func uploadEncryptedVideoToFirebase(fileURL: URL, recordingEntity: RecordingEntity, accelPointsToSave: [AccelPoint], savedOrientation: UIDeviceOrientation, duration: Double) {
        guard let subject = selectedSubject else { return }
        let storage = Storage.storage()
        let fileName = "videos/\(UUID().uuidString).mov"
        let storageRef = storage.reference().child(fileName)
        storageRef.putFile(from: fileURL, metadata: nil) { metadata, error in
            if let error = error {
                print("Video upload failed: \(error.localizedDescription)")
                self.updateRecordingEntity(subject: subject, recordingEntity: recordingEntity, fileURL: fileURL.path, cloudURL: nil, accelPointsToSave: accelPointsToSave, savedOrientation: savedOrientation, synced: false, duration: duration)
                return
            }
            storageRef.downloadURL { url, error in
                let downloadURL = url?.absoluteString
                self.updateRecordingEntity(subject: subject, recordingEntity: recordingEntity, fileURL: fileURL.path, cloudURL: downloadURL, accelPointsToSave: accelPointsToSave, savedOrientation: savedOrientation, synced: true, duration: duration)
            }
        }
    }
    
    //because we upload after we save local, we need to update the local with cloud URL
    func updateRecordingEntity(subject: SubjectEntity, recordingEntity: RecordingEntity, fileURL: String, cloudURL: String?, accelPointsToSave: [AccelPoint], savedOrientation: UIDeviceOrientation, synced: Bool, duration: Double) {
        guard let viewContext = self.viewContext else { return }
        recordingEntity.synced = synced
        recordingEntity.cloudUrl = cloudURL
        let syncEnabled = UserDefaults.standard.bool(forKey: "syncEnabled")
        try? viewContext.save()
        //print(syncEnabled)
        if syncEnabled {
            guard let uid = Auth.auth().currentUser?.uid else { return }
            //print("Sync Enabled")
            let db = Firestore.firestore()
            let recordingData: [String: Any] = [
                "recordingId": recordingEntity.recordingId?.uuidString ?? "",
                "ownerId" : uid,
                "subjectID": subject.subjectID?.uuidString ?? "",
                "timestamp": Timestamp(date: Date()),
                "localUrl": fileURL,
                "cloudUrl": cloudURL ?? "",
                "warnings": recordingEntity.warnings ?? [],
                "accelPoints": accelPointsToSave.map{
                    ["time": Timestamp(date: $0.time), "ax": $0.ax, "ay": $0.ay]
                },
                "orientation": savedOrientation.isPortrait ? "portrait" : "landscape",
                "duration": duration,
                "synced": synced
            ]
            db.collection("recordings").addDocument(data: recordingData)
        }
        self.warningMessages.clear()
        self.warningMessages.clearHistory()
    }

    //motion detection manager
    func startMonitoringMotion() {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 0.4
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self = self, let motion = data else { return }
            let gravity = motion.gravity
            let newOrientation: UIDeviceOrientation
            
            if abs(gravity.x) > abs(gravity.y) {
                newOrientation = gravity.x > 0 ? .landscapeLeft : .landscapeRight
            } else {
                newOrientation = gravity.y > 0 ? .portraitUpsideDown : .portrait
            }
            if orienatation != newOrientation {
                self.orienatation = newOrientation
                //print("orientation changed to \(newOrientation)")
            }
            let total = abs(motion.userAcceleration.x) + abs(motion.userAcceleration.y) + abs(motion.userAcceleration.z)
            if total > 0.02 && !self.isShakyWarningShown {
                DispatchQueue.main.async {
                    self.warningMessages.add("Camera is unstable", saveHistory: self.saveHistory)
                }
                self.isShakyWarningShown = true
            } else if total < 0.02 && self.isShakyWarningShown {
                DispatchQueue.main.async {
                    self.warningMessages.remove(text: "Camera is unstable")
                }
                self.isShakyWarningShown = false
            }
        }
    }
    func stopMonitoringMotion() {
        motionManager.stopDeviceMotionUpdates()
        isShakyWarningShown = false
        DispatchQueue.main.async {
            self.warningMessages.clear()
        }
    }
    
    //while we record we need to fix iso and shutter speed for proper calculation
    private func fixISOAndShutter() {
        guard let device = videoDevice else { return }
        guard selectedExposureMode == true else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                
                let currentISO = device.iso
                let currentShutterSpeed = device.exposureDuration
                
                if device.isExposureModeSupported(.custom) {
                    device.setExposureModeCustom(duration: currentShutterSpeed, iso: currentISO, completionHandler: nil)
                }
                device.unlockForConfiguration()
            } catch {
                print("Failed to Lock device for configuration: \(error)")
            }
            
        }
    }
    
    //after recording shutter speed and iso can be unfixed
    private func unfixISOAndShutter() {
        guard let device = videoDevice else { return }
        guard selectedExposureMode == true else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                
                if device.isExposureModeSupported(.autoExpose) {
                    device.exposureMode = .autoExpose
                }
                device.unlockForConfiguration()
            }
            catch {
                print("Failed to Lock device for configuration: \(error)")
            }
            
        }
    }
    
    //buffer to capture the actual video
    func captureOutput(
      _ output: AVCaptureOutput,
      didOutput sampleBuffer: CMSampleBuffer,
      from connection: AVCaptureConnection ) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // QR tracking
        if startTracking {
            tracker.initiateTracking(
              from: buffer,
              qrId: desiredQrToTrack
            )
            startTracking = false
        }
        tracker.processFrame(from: buffer)

        // QR count on main
        DispatchQueue.main.async {
            self.qrCodesCount = self.tracker.detections.count
        }
          
        // Low‑light detection
          if isLowLightDetectionEnabled {
              if let device = videoDevice {
                  let iso = device.iso
                  let dur = CMTimeGetSeconds(
                    device.exposureDuration
                  )
                  let isLow = iso > 800 || dur > 0.05
                  if isLow && !isLowLightWarningShown {
                      DispatchQueue.main.async {
                          self.warningMessages.add(
                            "Low light detected",
                            saveHistory: self.saveHistory
                          )
                      }
                      isLowLightWarningShown = true
                  } else if !isLow && isLowLightWarningShown {
                      DispatchQueue.main.async {
                          self.warningMessages.remove(
                            text: "Low light detected"
                          )
                      }
                      isLowLightWarningShown = false
                  }
              }
          }
    }
    
    //Depth Calculation
    private func checkDepthCapability() -> Bool {
        guard let device = videoDevice else { return false }
        
        let depthFormats = device.formats.filter { format in
            format.supportedDepthDataFormats.count > 0
        }
        
        return !depthFormats.isEmpty
    }
    //Filter depth output
    func depthDataOutput(_ output: AVCaptureDepthDataOutput,
                         didOutput depthData: AVDepthData,
                         timestamp: CMTime,
                         connection: AVCaptureConnection) {
        let depthPixelBuffer = depthData.depthDataMap
        CVPixelBufferLockBaseAddress(depthPixelBuffer, .readOnly)

        let width = CVPixelBufferGetWidth(depthPixelBuffer)
        let height = CVPixelBufferGetHeight(depthPixelBuffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(depthPixelBuffer)
        guard let floatBuffer = CVPixelBufferGetBaseAddress(depthPixelBuffer)?.assumingMemoryBound(to: Float32.self) else {
            CVPixelBufferUnlockBaseAddress(depthPixelBuffer, .readOnly)
            return
        }

        let centerX = width / 2
        let centerY = height / 2
        
        let regionSize = min(width / 4, height / 4)
        var validDepths: [Float] = []
        
        //chose a bunch of regions for better calc
        let regions = [
            (centerX, centerY),
            (centerX - width/6, centerY),
            (centerX + width/6, centerY),
            (centerX, centerY - height/6),
            (centerX, centerY + height/6)
        ]
        
        for (regionCenterX, regionCenterY) in regions {
            let startX = max(0, regionCenterX - regionSize / 4)
            let endX = min(width, regionCenterX + regionSize / 4)
            let startY = max(0, regionCenterY - regionSize / 4)
            let endY = min(height, regionCenterY + regionSize / 4)
            
            for y in startY..<endY {
                for x in startX..<endX {
                    let index = y * (rowBytes / MemoryLayout<Float32>.size) + x
                    let depth = floatBuffer[index]
                    
                    if !depth.isNaN && !depth.isInfinite && depth > 0.001 && depth < 10.0 {
                        validDepths.append(depth)
                    }
                }
            }
        }

        CVPixelBufferUnlockBaseAddress(depthPixelBuffer, .readOnly)
        
        guard !validDepths.isEmpty else {
            DispatchQueue.main.async {
                self.depthInMeter = nil
            }
            return
        }
        validDepths.sort()
        let medianDepth = validDepths[validDepths.count / 2]
        DispatchQueue.main.async {
            if let currentDepth = self.depthInMeter {
                self.depthInMeter = currentDepth * 0.7 + medianDepth * 0.3
            } else {
                self.depthInMeter = medianDepth
            }
            //print("Depth\(String(describing: self.depthInMeter))")
        }
    }
    

}
