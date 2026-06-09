import Foundation
import SwiftData

enum WorkoutType: String, Codable, CaseIterable {
    case maxHang = "Max Hang"
    case repeaters = "7:3 Repeaters"
}

enum GripType: String, Codable, CaseIterable {
    case halfCrimp = "Half Crimp"
    case fullCrimp = "Full Crimp"
    case openHand = "Open Hand"
    case pinch = "Pinch"
    case sloper = "Sloper"
}

@Model
final class WorkoutSession {
    var date: Date
    var workoutType: WorkoutType = WorkoutType.maxHang
    @Relationship(deleteRule: .cascade, inverse: \HangSet.session)
    var sets: [HangSet]

    init(date: Date, workoutType: WorkoutType = .maxHang) {
        self.date = date
        self.workoutType = workoutType
        self.sets = []
    }
}

enum HandSide: String, Codable, CaseIterable {
    case left = "Left"
    case right = "Right"
}

enum FingerName: String, Codable, CaseIterable {
    case index = "Index"
    case middle = "Middle"
    case ring = "Ring"
    case pinky = "Pinky"
    case thumb = "Thumb"
}

enum InjuryType: String, Codable, CaseIterable {
    case a2Pulley = "A2 Pulley"
    case a4Pulley = "A4 Pulley"
    case flexorTendon = "Flexor Tendon"
    case synovitis = "Synovitis"
    case other = "Other"
}

enum InjurySeverity: String, Codable, CaseIterable {
    case mild = "Mild"
    case moderate = "Moderate"
    case severe = "Severe"
}

@Model
final class FingerInjury {
    var onsetDate: Date
    var resolutionDate: Date?
    var hand: HandSide
    var finger: FingerName
    var injuryType: InjuryType
    var severity: InjurySeverity
    var notes: String

    init(
        onsetDate: Date,
        resolutionDate: Date? = nil,
        hand: HandSide,
        finger: FingerName,
        injuryType: InjuryType,
        severity: InjurySeverity,
        notes: String = ""
    ) {
        self.onsetDate = onsetDate
        self.resolutionDate = resolutionDate
        self.hand = hand
        self.finger = finger
        self.injuryType = injuryType
        self.severity = severity
        self.notes = notes
    }
}

@Model
final class HangSet {
    var gripType: GripType
    var hangTimeSeconds: Int
    var reps: Int
    var setRestSeconds: Int?
    var repRestSeconds: Int?
    var weightAddedLbs: Double
    var session: WorkoutSession?

    init(
        gripType: GripType,
        hangTimeSeconds: Int,
        reps: Int,
        setRestSeconds: Int? = nil,
        repRestSeconds: Int? = nil,
        weightAddedLbs: Double
    ) {
        self.gripType = gripType
        self.hangTimeSeconds = hangTimeSeconds
        self.reps = reps
        self.setRestSeconds = setRestSeconds
        self.repRestSeconds = repRestSeconds
        self.weightAddedLbs = weightAddedLbs
    }
}
