//
//  WorldTracker.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 22.02.2024.
//

import ARKit

/// Head pose from ARKit: between the eyes, x right, y up, -z forward (the same axes
/// as SteamVR), in a world whose origin is on the floor under the recentered head.
final class WorldTracker: NSObject, ARSessionDelegate {
    private let dispatchQueue: DispatchQueue
    private let configuration: ARWorldTrackingConfiguration
    private let arSession: ARSession

    private let isTrackOrientation: Bool
    private let isTrackPosition: Bool

    private let poseLock = NSLock()
    private var rawHead = matrix_identity_float4x4
    private var recenterTransform = matrix_identity_float4x4
    private var recenterRequested = true
    private var headToWorldRecentered = matrix_identity_float4x4
    // The last two recentered poses with their ARKit timestamps, for prediction.
    private var previous: (time: Double, head: simd_float4x4)?
    private var latest: (time: Double, head: simd_float4x4)?

    // Eyes' center relative to the rear camera, in ARKit camera axes (the phone in
    // UI landscape-right: top of the phone on the viewer's left). Estimates for an
    // iPhone 16 Pro in the headset tray: the camera sits ~55 mm left of and ~15 mm
    // above the screen center, and the eyes are ~60 mm behind the phone.
    static let eyesFromCamera = SIMD3<Float>(0.055, -0.015, 0.06)

    init(isTrackOrientation: Bool, isTrackPosition: Bool) {
        print("World tracking params: isTrackOrientation: \(isTrackOrientation), isTrackPosition: \(isTrackPosition)")

        self.isTrackOrientation = isTrackOrientation
        self.isTrackPosition = isTrackPosition

        dispatchQueue = .init(label: "ARWorldTrackingSource", qos: .userInteractive)

        configuration = .init()
        configuration.planeDetection = .horizontal

        arSession = ARSession()

        super.init()
        arSession.delegate = self
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        updateHeadPose(frame)
    }

    func start() {
        // Start ar session
        dispatchQueue.async { [weak self] in
            guard let self = self else { return }
            self.arSession.run(self.configuration)
        }
    }

    func stop() {
        arSession.pause()
    }

    /// Head pose (between the eyes) in recentered world space, meters.
    func headToWorld() -> simd_float4x4 {
        poseLock.lock()
        defer { poseLock.unlock() }
        return headToWorldRecentered
    }

    /// Head pose predicted to `time` (CACurrentMediaTime clock): the rotation keeps
    /// turning at the rate between the last two ARKit frames, for at most 50 ms.
    /// ARKit updates at 60 Hz, so this keeps a 120 Hz display from juddering.
    func headToWorld(at time: Double) -> simd_float4x4 {
        poseLock.lock()
        defer { poseLock.unlock() }
        guard let l = latest, let p = previous, l.time > p.time else { return headToWorldRecentered }
        var delta = simd_quatf(l.head.rotation3x3) * simd_quatf(p.head.rotation3x3).inverse
        if delta.real < 0 { delta = simd_quatf(vector: -delta.vector) }   // shortest way round
        let ahead = Float(min(max(time - l.time, 0), 0.05))
        guard delta.angle > 1e-5, ahead > 0 else { return l.head }
        let rate = delta.angle / Float(l.time - p.time)
        let predicted = simd_quatf(angle: rate * ahead, axis: delta.axis) * simd_quatf(l.head.rotation3x3)
        var m = simd_float4x4(simd_normalize(predicted))
        m.columns.3 = l.head.columns.3
        return m
    }

    /// Make the current view the forward direction, and put the head at the
    /// standing eye height above the origin.
    func recenter() {
        poseLock.lock()
        recenterRequested = true
        poseLock.unlock()
    }

    private func updateHeadPose(_ frame: ARFrame) {
        // ARKit's camera axes match the device in UI landscape-right: x right, y up,
        // +z out of the screen toward the viewer. In landscape-left, turn 180° about z.
        let orientation = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.interfaceOrientation
        let flip: Float = orientation == .landscapeLeft ? -1 : 1
        var cameraToHead = matrix_identity_float4x4
        cameraToHead.columns.0 = SIMD4<Float>(flip, 0, 0, 0)
        cameraToHead.columns.1 = SIMD4<Float>(0, flip, 0, 0)
        // The offset is fixed to the phone, so it's in camera axes either way.
        let e = WorldTracker.eyesFromCamera
        cameraToHead.columns.3 = SIMD4<Float>(e.x, e.y, e.z, 1)
        var head = frame.camera.transform * cameraToHead
        if !isTrackOrientation {
            let position = head.columns.3
            head = matrix_identity_float4x4
            head.columns.3 = position
        }

        poseLock.lock()
        defer { poseLock.unlock() }
        let lastPosition = rawHead.columns.3
        rawHead = head
        if !isTrackPosition {
            rawHead.columns.3 = SIMD4<Float>(0, 0, 0, 1)
        } else if case .normal = frame.camera.trackingState {
            // Tracking is good: take the new position.
        } else {
            // Tracking limited or lost: keep turning, hold the last position.
            rawHead.columns.3 = lastPosition
        }
        if recenterRequested {
            recenterRequested = false
            let forward = -SIMD3<Float>(rawHead.columns.2.x, rawHead.columns.2.y, rawHead.columns.2.z)
            let yaw = atan2(-forward.x, -forward.z)
            var unYaw = matrix_identity_float4x4
            unYaw.columns.0 = SIMD4<Float>(cos(yaw), 0, sin(yaw), 0)
            unYaw.columns.2 = SIMD4<Float>(-sin(yaw), 0, cos(yaw), 0)
            var unMove = matrix_identity_float4x4
            unMove.columns.3 = SIMD4<Float>(-rawHead.columns.3.x, -rawHead.columns.3.y, -rawHead.columns.3.z, 1)
            var raise = matrix_identity_float4x4
            raise.columns.3 = SIMD4<Float>(0, VRSettings.current.eyeHeightM, 0, 1)
            recenterTransform = raise * unYaw * unMove
            latest = nil   // don't predict across the jump
        }
        headToWorldRecentered = recenterTransform * rawHead
        previous = latest
        latest = (frame.timestamp, headToWorldRecentered)
    }
}
