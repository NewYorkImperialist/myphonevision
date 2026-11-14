//
//  WorldTracker.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 22.02.2024.
//

import ARKit
import CoreMotion

final class WorldTracker: NSObject, ARSessionDelegate {
    private let dispatchQueue: DispatchQueue
    private let configuration: ARWorldTrackingConfiguration
    private let arSession: ARSession
    
    #if DEBUG
    private var lastTickTime: Int64 = 0
    private var tps = 0
    #endif
    
    // FIXME: Monkey code
    private var position: (Float, Float, Float) = (Float.zero, Float.zero + 1.6, Float.zero)
    private var rotation: CMQuaternion = .init()
    
    private let isTrackOrientation: Bool
    private let isTrackPosition: Bool

    // Head pose between the eyes, in ARKit world space, then recentered.
    private let poseLock = NSLock()
    private var rawHead = matrix_identity_float4x4
    private var recenterTransform = matrix_identity_float4x4
    private var recenterRequested = true
    private var headToWorldRecentered = matrix_identity_float4x4

    // Eyes' center relative to the rear camera, in ARKit camera axes (the phone in
    // UI landscape-right: top of the phone on the viewer's left). Estimates for an
    // iPhone 16 Pro in the headset tray: the camera sits ~55 mm left of and ~15 mm
    // above the screen center, and the eyes are ~60 mm behind the phone.
    static let eyesFromCamera = SIMD3<Float>(0.055, -0.015, 0.06)

    init(isTrackOrientation: Bool, isTrackPosition: Bool) {
        print("World tracking params: isTrackOrientation: \(isTrackOrientation), isTrackPosition: \(isTrackPosition)")
        
        self.isTrackOrientation = isTrackOrientation
        self.isTrackPosition = isTrackPosition
        
        dispatchQueue = .init(label: "ARWorldTrackingSource", qos: .background)
        
        configuration = .init()
        configuration.planeDetection = .horizontal
        
        arSession = ARSession()
        
        super.init()
        arSession.delegate = self
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        updateHeadPose(frame)

        if isTrackOrientation {
            if let frameEuler = arSession.currentFrame?.camera.eulerAngles {
                let r = frameEuler
                
                // Get quaternion components
                let cr = cos(r.x * 0.5)
                let sr = sin(r.x * 0.5)
                let cp = cos(r.y * 0.5)
                let sp = sin(r.y * 0.5)
                let cy = cos(r.z * 0.5)
                let sy = sin(r.z * 0.5)
                
                // Get quaternion values
                let w = (cr * cp * cy + sr * sp * sy)
                let x = (sr * cp * cy - cr * sp * sy)
                let y = (cr * sp * cy + sr * cp * sy)
                let z = (cr * cp * sy - sr * sp * cy)
                
                self.rotation = .init(x: Double(x), y: Double(y), z: Double(z), w: Double(w))
            }
        }
        
        if isTrackPosition {
            if let pos = arSession.currentFrame?.camera.transform.columns.3 {
                self.position = (pos.x, pos.y + 1.0, pos.z)
            }
        }
        
        #if DEBUG
        tps += 1
        if Int64.getCurrentMillis() - lastTickTime > 1000 {
            lastTickTime = Int64.getCurrentMillis()
            // print("World tracker tps is \(tps)")
            tps = 0
        }
        #endif
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
    
    /// Head pose (between the eyes, x right, y up, -z forward) in recentered world space.
    func headToWorld() -> simd_float4x4 {
        poseLock.lock()
        defer { poseLock.unlock() }
        return headToWorldRecentered
    }

    /// Make the current view the forward direction and the current position the origin.
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
        let head = frame.camera.transform * cameraToHead

        poseLock.lock()
        defer { poseLock.unlock() }
        if case .normal = frame.camera.trackingState {
            rawHead = head
        } else {
            // Tracking limited or lost: keep turning, hold the last position.
            let position = rawHead.columns.3
            rawHead = head
            rawHead.columns.3 = position
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
            recenterTransform = unYaw * unMove
        }
        headToWorldRecentered = recenterTransform * rawHead
    }

    /// Get device position
    func getPosition() -> (Float, Float, Float) {
        return position
    }
    
    /// Get device euler rotation
    func getRotation() -> CMQuaternion {
        return rotation
    }
    
    /// Get device quaterion rotation
    func getQuaterionRotation() -> AlvrQuat {
        let r = getRotation()
        
        return AlvrQuat.init(x: Float(r.x), y: Float(r.y), z: Float(r.z), w: Float(r.w))
    }
}
