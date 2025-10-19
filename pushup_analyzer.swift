import Foundation
import simd // For efficient vector math

// --- Step 1: Define Codable Structs to Match Your JSON Data ---

/// Represents a single 3D landmark with visibility.
struct Landmark: Codable {
    let x: Double
    let y: Double
    let z: Double
    let visibility: Double
}

/// Represents a single frame of data from your pose estimation model.
struct FrameData: Codable {
    let relativeTime: Double
    let landmarks: [String: Landmark]

    enum CodingKeys: String, CodingKey {
        case relativeTime = "relative_time"
        case landmarks
    }
}

// --- Step 2: The Main Analyzer Class ---

class PushupAnalyzer {

    // MARK: - Public Properties
    private(set) var repCount = 0
    private(set) var feedbackLog: [String] = []

    // MARK: - Private State Tracking
    private var stage: String = "up"
    private var lastFeedback: String = ""
    private var minAngleInRep: Double = 180.0
    private var frameCount = 0
    
    // Frame Buffer
    private let frameBufferCount = 4
    private var upFrames = 0
    private var downFrames = 0

    // Timers for Tempo
    private var repStartTime: Double = 0.0

    // MARK: - Form Thresholds (Tunable)
    private let depthThresholdAngle: Double = 100.0
    private let repThreshold: Double = 150.0
    private let bodyStraightAngleMin: Double = 150.0
    private let elbowFlareAngleMax: Double = 80.0
    private let repTooFastSeconds: Double = 1.0

    // MARK: - Public Methods

    /// Processes a single frame of landmark data and returns feedback.
    /// - Parameter frameData: The parsed data for the current frame.
    /// - Returns: An array of feedback strings for the current frame.
    func processFrame(frameData: FrameData) -> [String] {
        frameCount += 1
        let landmarks = frameData.landmarks
        let currentTime = frameData.relativeTime
        var feedbackThisFrame: [String] = []

        do {
            // --- Get key landmarks ---
            guard
                let shoulder = landmarks["right_shoulder"],
                let elbow = landmarks["right_elbow"],
                let wrist = landmarks["right_wrist"],
                let hip = landmarks["right_hip"],
                let ankle = landmarks["right_ankle"]
            else {
                throw AnalyzerError.missingLandmark("Required landmark not found.")
            }

            // --- Calculate all relevant angles ---
            let elbowAngle = calculateAngle(a: shoulder, b: elbow, c: wrist)
            let bodyAngle = calculateAngle(a: shoulder, b: hip, c: ankle)
            let elbowFlareAngle = calculateAngle(a: hip, b: shoulder, c: elbow)
            
            // --- 1. Body Straightness Check ---
            if bodyAngle < bodyStraightAngleMin {
                let feedback = "Keep your back straight!"
                if lastFeedback != feedback {
                    feedbackThisFrame.append(feedback)
                    lastFeedback = feedback
                }
            } else {
                lastFeedback = ""
            }

            // --- 2. Elbow Flare Check ---
            if elbowFlareAngle > elbowFlareAngleMax {
                feedbackThisFrame.append("Tuck your elbows in a bit!")
            }

            // --- 3. Rep Counting, Depth, and State Logic with Frame Buffer ---
            if elbowAngle < repThreshold {
                downFrames += 1
                upFrames = 0
            } else {
                upFrames += 1
                downFrames = 0
            }

            // A rep begins when the user has been 'down' for enough frames.
            if stage == "up" && downFrames >= frameBufferCount {
                stage = "down"
                repStartTime = currentTime
                minAngleInRep = elbowAngle // Start tracking
            }
            // While in the 'down' phase...
            else if stage == "down" {
                minAngleInRep = min(minAngleInRep, elbowAngle)

                // A rep attempt ends when the user has been 'up' for enough frames.
                if upFrames >= frameBufferCount {
                    stage = "up"

                    // --- 4. Depth Check (at the end of the rep) ---
                    if minAngleInRep > depthThresholdAngle {
                        feedbackThisFrame.append("Go deeper on your push-ups!")
                    } else {
                        repCount += 1 // Only count good reps
                    }
                    
                    // --- 5. Tempo Check ---
                    let repDuration = currentTime - repStartTime
                    if repDuration < repTooFastSeconds && repStartTime > 0 {
                        feedbackThisFrame.append("Slow down your reps!")
                    }

                    // Reset for the next rep
                    repStartTime = 0
                    minAngleInRep = 180.0
                }
            }
            
            // Add new, unique feedback to the session log
            for item in feedbackThisFrame {
                if !feedbackLog.contains(item) {
                    feedbackLog.append(item)
                }
            }
            
            return feedbackThisFrame

        } catch {
            return ["An error occurred: \(error.localizedDescription)"]
        }
    }
    
    /// Resets the analyzer to its initial state for a new workout session.
    func reset() {
        repCount = 0
        feedbackLog = []
        stage = "up"
        lastFeedback = ""
        minAngleInRep = 180.0
        frameCount = 0
        upFrames = 0
        downFrames = 0
        repStartTime = 0.0
    }

    // MARK: - Private Helpers

    /// Calculates the angle between three landmarks in 2D space (x, y).
    private func calculateAngle(a: Landmark, b: Landmark, c: Landmark) -> Double {
        // Use SIMD for efficient 2D vector operations
        let pA = SIMD2<Double>(a.x, a.y)
        let pB = SIMD2<Double>(b.x, b.y)
        let pC = SIMD2<Double>(c.x, c.y)

        let ba = pA - pB
        let bc = pC - pB
        
        // Calculate cosine of the angle using the dot product
        let cosineAngle = simd_dot(ba, bc) / (simd_length(ba) * simd_length(bc))
        
        // Use acos to get the angle in radians, then convert to degrees
        let angle = acos(cosineAngle)
        return angle * (180.0 / .pi)
    }
    
    enum AnalyzerError: Error, LocalizedError {
        case missingLandmark(String)
        var errorDescription: String? {
            switch self {
            case .missingLandmark(let message):
                return message
            }
        }
    }
}