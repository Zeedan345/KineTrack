//
//  CamerePreview.swift
//  Heart Sensor
//
//  Created by Zeedan Khan
//

import SwiftUI
import AVFoundation

class VideoPreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }
    
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
    
    var session: AVCaptureSession? {
        get {
            return videoPreviewLayer.session
        }
        set {
            videoPreviewLayer.session = newValue
        }
    }
}


struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    @Binding var preview: VideoPreviewView

    // This creates the view object and configures its initial state.
    func makeUIView(context: Context) -> VideoPreviewView {
        DispatchQueue.main.async {
            self.preview = context.coordinator.view
        }
        return context.coordinator.view
    }
    func updateUIView(_ uiView: VideoPreviewView, context: Context) {
        // No code needed here
    }
    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    class Coordinator {
        let view: VideoPreviewView
        
        init(session: AVCaptureSession) {
            self.view = VideoPreviewView()
            self.view.session = session
            self.view.backgroundColor = .black
            self.view.videoPreviewLayer.videoGravity = .resizeAspectFill //Fill the screen
            self.view.videoPreviewLayer.connection?.videoOrientation = .portrait
        }
    }

}

