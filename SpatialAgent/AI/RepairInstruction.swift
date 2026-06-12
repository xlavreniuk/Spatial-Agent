//
//  RepairInstruction.swift
//  SpatialAgent
//
//  Created by Andrii on 12/06/2026.
//

import Foundation

enum RepairInstructionAction: String, Codable, CaseIterable {
    case unscrew = "UNSCREW"
    case tighten = "TIGHTEN"
    case pull = "PULL"
    case push = "PUSH"
    case lift = "LIFT"
    case lower = "LOWER"
    case open = "OPEN"
    case close = "CLOSE"
    case slideLeft = "SLIDE_LEFT"
    case slideRight = "SLIDE_RIGHT"
    case remove = "REMOVE"
    case install = "INSTALL"
    case rotateCW = "ROTATE_CW"
    case rotateCCW = "ROTATE_CCW"
    case check = "CHECK"
    case warning = "WARNING"
    case complete = "COMPLETE"
}

struct RepairInstruction: Codable, Equatable {
    let action: RepairInstructionAction
    let target: String
}

struct RepairStep: Codable, Equatable {
    let step: Int
    let voice: String
    let instructions: [RepairInstruction]
}

struct DetectedObject: Codable, Equatable {
    let id: String
    let label: String
}

struct VisionContext: Codable, Equatable {
    let objects: [DetectedObject]
}
