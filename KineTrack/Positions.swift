import Foundation
//
//  Positions.swift
//  KineTrack
//
//  Created by Zeedan on 10/18/25.
//

struct Position: Identifiable, Equatable {
    let id: UUID = UUID()
    let name: String
    let icon: String

    static let allPositions = [
        Position(name: "Squat", icon: "figure.strengthtraining.traditional"),
        Position(name: "PushUps", icon: "figure.walk"),
    ]
}
