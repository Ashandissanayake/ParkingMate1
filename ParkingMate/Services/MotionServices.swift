import Foundation
import CoreMotion
import Observation

extension ActivitySample {
    init(_ a: CMMotionActivity) {
        self.init(automotive: a.automotive, walking: a.walking, running: a.running, stationary: a.stationary,
                  confidence: a.confidence == .high ? .high : (a.confidence == .medium ? .medium : .low))
    }
}
@MainActor
@Observable
final class MotionActivityService {
    private(set) var isRunning = false
    private(set) var status = "Not monitoring"
    private(set) var lastDetection: Date?
    private(set) var isAvailable = CMMotionActivityManager.isActivityAvailable()
    @ObservationIgnored var onParked: (() -> Void)?

    @ObservationIgnored private let manager = CMMotionActivityManager()
    @ObservationIgnored private var machine = ParkingDetectionStateMachine()

    func start() {
        guard isAvailable, !isRunning else { return }
        machine.reset()
        isRunning = true
        status = "Waiting for you to drive…"
        manager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let activity else { return }
            let sample = ActivitySample(activity)
            Task { @MainActor in self?.handle(sample) }
        }
    }

    func stop() {
        manager.stopActivityUpdates()
        isRunning = false
        status = "Not monitoring"
    }

    func handle(_ sample: ActivitySample) {
        if sample.automotive { status = "Driving" }
        else if sample.walking || sample.running { status = "On foot" }
        else if sample.stationary { status = "Vehicle motion stopped" }
        if machine.ingest(sample) {
            lastDetection = .now
            status = "Parking detected"
            onParked?()
        }
    }
}
@MainActor
@Observable
final class AltitudeService {
    private(set) var relativeAltitude: Double?
    private(set) var isAvailable = CMAltimeter.isRelativeAltitudeAvailable()
    @ObservationIgnored private let altimeter = CMAltimeter()
    private var isRunning = false

    var estimatedFloor: String? {
        relativeAltitude.map { FloorEstimator.label(relativeAltitude: $0) }
    }

    func start() {
        guard isAvailable, !isRunning else { return }
        isRunning = true
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let meters = data?.relativeAltitude.doubleValue else { return }
            Task { @MainActor in self?.relativeAltitude = meters }
        }
    }
    func recalibrate() {
        altimeter.stopRelativeAltitudeUpdates()
        relativeAltitude = 0
        isRunning = false
        start()
    }

    func stop() {
        altimeter.stopRelativeAltitudeUpdates()
        isRunning = false
    }
}
