//
//  Utilities.swift
//  Heart Sensor
//
//  Created by Taebi Lab on 6/17/25.
//

import Foundation
import Security
import AVKit
import CoreData

func formatTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.timeStyle = .medium
    return formatter.string(from: date)
}
func extractMetaData(_ url: URL) -> (fileSize: Int64, startTime: Date, duration: Double?, res: CGSize, fps: Float) {
    var fileSize: Int64 = 0
    var startTime: Date = Date()
    var duration: Double?
    var res: CGSize = .zero
    var fps: Float = 0

    if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
        if let size = attrs[.size] as? NSNumber {
            fileSize = size.int64Value
        }
        if let created = attrs[.creationDate] as? Date {
            startTime = created
        }
    }

    let asset = AVAsset(url: url)
    let seconds = CMTimeGetSeconds(asset.duration)
    duration = seconds.isFinite ? seconds : nil

    if let track = asset.tracks(withMediaType: .video).first {
        res = track.naturalSize
        fps = track.nominalFrameRate
    }

    return (fileSize, startTime, duration, res, fps)
}
func findAvailableCamera(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
    let discoverySession = AVCaptureDevice.DiscoverySession(
        deviceTypes: [ .builtInLiDARDepthCamera,.builtInWideAngleCamera, .builtInDualCamera,.builtInDualWideCamera, .builtInTripleCamera, .builtInTelephotoCamera],
        mediaType: .video,
        position: position
        )
    return discoverySession.devices.first
}
func discoverSupportedFormats(position: AVCaptureDevice.Position) -> [CameraFormatOption] {
    guard let device = findAvailableCamera(position: position) else {
        print("No Available Camera")
        return []
    }
    var options = [CameraFormatOption]()
//    let otherFormats = device.formats.filter { !$0.supportedDepthDataFormats.isEmpty }
//    print(otherFormats)
    for format in device.formats {
        let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        guard dims.width >= 640 else { continue }
        let rates = format.videoSupportedFrameRateRanges
            .flatMap { Int($0.minFrameRate)...Int($0.maxFrameRate) }
        guard !rates.isEmpty else { continue }
        options.append(CameraFormatOption(
            format:    format,
            width:     dims.width,
            height:    dims.height,
            frameRates: Array(Set(rates)).sorted()
        ))
    }
    let grouped = Dictionary(grouping: options, by: { $0.resolutionLabel })
    let unique  = grouped.compactMap {
        $0.value.max(by: { a,b in (a.frameRates.max() ?? 0) < (b.frameRates.max() ?? 0) })
    }
    let sorted = unique.sorted {
        let isA4K = ($0.width == 3840 && $0.height == 2160)
        let isB4K = ($1.width == 3840 && $1.height == 2160)

        if isA4K && !isB4K {
            return true
        } else if !isA4K && isB4K {
            return false
        } else {
            return $0.width * $0.height > $1.width * $1.height
        }
    }
    return sorted
}

func calculateTime(_ time: Date, start: Double) -> Double {
    return (time.timeIntervalSince1970 - start)
}
