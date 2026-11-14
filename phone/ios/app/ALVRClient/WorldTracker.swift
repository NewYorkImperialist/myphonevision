//
//  WorldTracker.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 22.02.2024.
//

import ARKit
import CoreMotion

/// Head pose from ARKit: between the eyes, x right, y up, -z forward (the same axes
/// as SteamVR), in a world whose origin is on the floor under the recentered head.
/// ARKit is the drift-free reference (60 Hz at best); between its frames, and ahead
/// in time, the orientation comes from the gyro (200 Hz).
final class WorldTracker: NSObject, ARSessionDelegate {
    private let dispatchQueue: DispatchQueue
    private let configuration: ARWorldTrackingConfiguration
    private let arSession: ARSession

    private let motionManager = CMMotionManager()
    private let motionQueue = OperationQueue()
    /// Gyro rotation integrated in device axes from an arbitrary start, with sample
    /// times (seconds since boot, the same clock as ARFrame.timestamp and
    /// CACurrentMediaTime). Only differences between two times are used.
    private var gyroHistory: [(time: Double, rotation: simd_quatf)] = []
    private var gyroRate = SIMD3<Float>(0, 0, 0)   // latest, rad/s, device axes
    /// Head axes in device axes. ARKit's camera axes are the device in landscape-right
    /// (x toward the bottom edge, y toward the right edge, z out of the screen); the
    /// head flips x and y in landscape-left. Set on the main thread.
    private var headAxesInDevice = simd_float3x3(SIMD3(0, -1, 0), SIMD3(1, 0, 0), SIMD3(0, 0, 1))
    private var flip: Float = 1

    private let isTrackOrientation: Bool
    private let isTrackPosition: Bool

    private let poseLock = NSLock()
    private var rawHead = matrix_identity_float4x4
    private var recenterTransform = matrix_identity_float4x4
    private var recenterRequested = true
    private var headToWorldRecentered = matrix_identity_float4x4
    // The latest recentered pose with its ARKit timestamp; the gyro carries it forward.
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
        // Ask for 60 frames/s explicitly (the default can come up at 30).
        if let format = ARWorldTrackingConfiguration.supportedVideoFormats.first(where: { $0.framesPerSecond == 60 }) {
            configuration.videoFormat = format
        }
        // AR passthrough extras, only when used (heat): LiDAR depth (depth modes, LiDAR
        // occlusion) and person segmentation (people & hands occlusion). If the phone
        // can't run both at once, person segmentation wins.
        let settings = VRSettings.current
        var wanted: ARConfiguration.FrameSemantics = []
        if settings.passthrough > 0.5 {
            if settings.lidarDepth > 0.5 || settings.occlusion > 1.5 { wanted.insert(.smoothedSceneDepth) }
            if settings.occlusion > 0.5 && settings.occlusion < 1.5 { wanted.insert(.personSegmentationWithDepth) }
        }
        for option in [wanted, wanted.subtracting(.smoothedSceneDepth), wanted.subtracting(.personSegmentationWithDepth)]
        where ARWorldTrackingConfiguration.supportsFrameSemantics(option) {
            configuration.frameSemantics = option
            break
        }
        print("ARKit frame semantics: wanted \(wanted.rawValue), using \(configuration.frameSemantics.rawValue)")

        arSession = ARSession()

        super.init()
        arSession.delegate = self
        // Deliver frames on our own queue, not the main queue next to rendering and UI.
        arSession.delegateQueue = dispatchQueue
        motionQueue.name = "Gyro"
        motionQueue.maxConcurrentOperationCount = 1
        motionQueue.qualityOfService = .userInteractive
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        updateHeadPose(frame)
        if let depth = frame.smoothedSceneDepth {
            depthSmoother.submit(depth: depth.depthMap, confidence: depth.confidenceMap)
        }
    }

    private let depthSmoother = DepthSmoother()

    /// Smoothed LiDAR depth for AR passthrough, if the depth setting is on.
    func smoothedDepth() -> DepthSmoother.Result? {
        return depthSmoother.latest()
    }

    func start() {
        updateInterfaceOrientation()
        NotificationCenter.default.addObserver(self, selector: #selector(updateInterfaceOrientation),
                                               name: UIDevice.orientationDidChangeNotification, object: nil)
        startGyro()
        // Start ar session
        dispatchQueue.async { [weak self] in
            guard let self = self else { return }
            self.arSession.run(self.configuration)
        }
    }

    func stop() {
        arSession.pause()
        motionManager.stopDeviceMotionUpdates()
        NotificationCenter.default.removeObserver(self)
    }

    /// Main thread: which landscape the UI is in decides the head axes.
    @objc private func updateInterfaceOrientation() {
        let orientation = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.interfaceOrientation
        let f: Float = orientation == .landscapeLeft ? -1 : 1
        poseLock.lock()
        flip = f
        headAxesInDevice = simd_float3x3(SIMD3(0, -f, 0), SIMD3(f, 0, 0), SIMD3(0, 0, 1))
        poseLock.unlock()
    }

    private func startGyro() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 200
        // deviceMotion's rotationRate is the bias-corrected gyro.
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let r = motion.rotationRate
            let rate = SIMD3<Float>(Float(r.x), Float(r.y), Float(r.z))
            self.poseLock.lock()
            defer { self.poseLock.unlock() }
            var rotation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
            if let last = self.gyroHistory.last {
                // Body-frame integration: R(t + dt) = R(t) * exp(rate * dt).
                let dt = Float(motion.timestamp - last.time)
                rotation = last.rotation
                if dt > 0, dt < 0.1, simd_length(rate) > 0 {
                    rotation = simd_normalize(rotation * simd_quatf(angle: simd_length(rate) * dt, axis: simd_normalize(rate)))
                }
            }
            self.gyroHistory.append((motion.timestamp, rotation))
            if self.gyroHistory.count > 400 { self.gyroHistory.removeFirst(self.gyroHistory.count - 400) }   // 2 s
            self.gyroRate = rate
        }
    }

    /// Integrated gyro rotation at `time`, interpolated; nil outside the history.
    private func gyroRotation(at time: Double) -> simd_quatf? {
        guard let first = gyroHistory.first, time >= first.time else { return nil }
        guard let i = gyroHistory.lastIndex(where: { $0.time <= time }) else { return nil }
        if i + 1 < gyroHistory.count {
            let a = gyroHistory[i], b = gyroHistory[i + 1]
            let u = Float((time - a.time) / (b.time - a.time))
            return simd_slerp(a.rotation, b.rotation, u)
        }
        return gyroHistory[i].rotation
    }

    /// Head pose (between the eyes) in recentered world space, meters.
    func headToWorld() -> simd_float4x4 {
        poseLock.lock()
        defer { poseLock.unlock() }
        return headToWorldRecentered
    }

    /// Head pose at `time` (CACurrentMediaTime clock), the same way for the pose sent
    /// to the server and the reprojection target: the latest ARKit orientation, turned
    /// by the gyro from that frame's time to its newest sample, then on at the newest
    /// gyro rate up to `time` (at most 100 ms ahead). With head prediction off in the
    /// lobby, `time` is capped at now. Position is the latest ARKit position.
    func headToWorld(at time: Double) -> simd_float4x4 {
        let target = VRSettings.current.prediction > 0.5 ? time : min(time, CACurrentMediaTime())
        poseLock.lock()
        defer { poseLock.unlock() }
        guard let l = latest else { return headToWorldRecentered }
        guard let fromFrame = gyroRotation(at: l.time), let newest = gyroHistory.last else { return l.head }
        // Rotation from the ARKit frame to the newest gyro sample, then extrapolated.
        var deltaDevice = fromFrame.inverse * newest.rotation
        let ahead = Float(min(max(target - newest.time, 0), 0.1))
        if ahead > 0, simd_length(gyroRate) > 0 {
            deltaDevice = deltaDevice * simd_quatf(angle: simd_length(gyroRate) * ahead, axis: simd_normalize(gyroRate))
        }
        // The same rotation in head axes: M^T * delta * M.
        let m = headAxesInDevice
        let deltaHead = simd_quatf(m.transpose * simd_float3x3(simd_normalize(deltaDevice)) * m)
        var out = simd_float4x4(simd_normalize(simd_quatf(l.head.rotation3x3) * deltaHead))
        out.columns.3 = l.head.columns.3
        return out
    }

    /// The latest rear-camera image with what's needed to line it up (AR passthrough).
    struct CameraFrame {
        let image: CVPixelBuffer              // YCbCr 4:2:0 biplanar, full range
        let intrinsics: simd_float3x3         // in image pixels
        let imageSize: SIMD2<Float>
        let headAtCapture: simd_float4x4      // recentered head pose when it was captured
        let cameraToHead: simd_float4x4       // the head in camera coordinates (head pose = camera pose * this): orientation flip + eye offset
        let frame: ARFrame                    // for ARMatteGenerator (person segmentation); only the latest is kept
    }
    private var cameraFrame: CameraFrame?

    func latestCameraFrame() -> CameraFrame? {
        poseLock.lock()
        defer { poseLock.unlock() }
        return cameraFrame
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
        // (This runs on the AR queue; the UI orientation is cached on the main thread.)
        poseLock.lock()
        let flip = self.flip
        poseLock.unlock()
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
        latest = (frame.timestamp, headToWorldRecentered)
        let resolution = frame.camera.imageResolution
        cameraFrame = CameraFrame(image: frame.capturedImage,
                                  intrinsics: frame.camera.intrinsics,
                                  imageSize: SIMD2(Float(resolution.width), Float(resolution.height)),
                                  headAtCapture: headToWorldRecentered, cameraToHead: cameraToHead, frame: frame)
    }
}

/// Turns ARKit's raw LiDAR depth (256 x 192, noisy, with holes and hard edges) into
/// something stable enough to warp the camera image with:
/// - a 32 x 24 grid of per-cell medians of confident samples, gaps filled, blurred
///   and smoothed over time, so the warp bends instead of tearing at edges;
/// - one scene depth: the median of the central cells, smoothed over time.
/// Runs on its own queue and skips frames while busy.
final class DepthSmoother {
    static let gridW = 32, gridH = 24
    struct Result {
        let grid: [Float16]       // gridW x gridH, meters along the camera's view axis, row-major from the image's top
        let full: [Float16]       // the depth map at full resolution (fullW x fullH), for occlusion
        let fullW: Int
        let fullH: Int
        let sceneDepth: Float
        let version: Int
    }
    
    private let queue = DispatchQueue(label: "Depth smoother", qos: .userInitiated)
    private let lock = NSLock()
    private var busy = false
    private var result: Result?
    private var grid = [Float](repeating: 0, count: gridW * gridH)
    private var sceneDepth: Float = 1.5
    private var version = 0
    
    func latest() -> Result? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
    
    func submit(depth: CVPixelBuffer, confidence: CVPixelBuffer?) {
        lock.lock()
        if busy { lock.unlock(); return }
        busy = true
        lock.unlock()
        queue.async { [self] in
            process(depth: depth, confidence: confidence)
            lock.lock()
            busy = false
            lock.unlock()
        }
    }
    
    private func process(depth: CVPixelBuffer, confidence: CVPixelBuffer?) {
        let gw = DepthSmoother.gridW, gh = DepthSmoother.gridH
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
        if let confidence { CVPixelBufferLockBaseAddress(confidence, .readOnly) }
        defer { if let confidence { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) } }
        guard let depthBase = CVPixelBufferGetBaseAddress(depth) else { return }
        let w = CVPixelBufferGetWidth(depth), h = CVPixelBufferGetHeight(depth)
        let depthRow = CVPixelBufferGetBytesPerRow(depth)
        let confBase = confidence.flatMap { CVPixelBufferGetBaseAddress($0) }
        let confRow = confidence.map { CVPixelBufferGetBytesPerRow($0) } ?? 0
        let cw = w / gw, ch = h / gh
        
        // Per-cell median of confident samples (every other pixel is plenty).
        var cells = [Float](repeating: .nan, count: gw * gh)
        var samples = [Float]()
        samples.reserveCapacity(cw * ch)
        for gy in 0..<gh {
            for gx in 0..<gw {
                samples.removeAll(keepingCapacity: true)
                var y = gy * ch
                while y < (gy + 1) * ch {
                    let row = (depthBase + y * depthRow).assumingMemoryBound(to: Float32.self)
                    let conf = confBase.map { ($0 + y * confRow).assumingMemoryBound(to: UInt8.self) }
                    var x = gx * cw
                    while x < (gx + 1) * cw {
                        let d = row[x]
                        if d > 0.1, d < 8, (conf?[x] ?? 2) >= 1 { samples.append(d) }   // medium or high confidence
                        x += 2
                    }
                    y += 2
                }
                if samples.count >= 4 {
                    samples.sort()
                    cells[gy * gw + gx] = samples[samples.count / 2]
                }
            }
        }
        
        // Scene depth: median of the valid cells in the middle half of the view.
        var central = [Float]()
        for gy in gh / 4..<gh * 3 / 4 {
            for gx in gw / 4..<gw * 3 / 4 where !cells[gy * gw + gx].isNaN {
                central.append(cells[gy * gw + gx])
            }
        }
        central.sort()
        let measuredScene = central.isEmpty ? sceneDepth : central[central.count / 2]
        
        // Fill gaps with the scene depth, then blur twice (3 x 3 box).
        for i in cells.indices where cells[i].isNaN { cells[i] = measuredScene }
        for _ in 0..<2 {
            var blurred = cells
            for gy in 0..<gh {
                for gx in 0..<gw {
                    var sum: Float = 0, n: Float = 0
                    for dy in -1...1 {
                        for dx in -1...1 {
                            let x = gx + dx, y = gy + dy
                            if x >= 0, x < gw, y >= 0, y < gh { sum += cells[y * gw + x]; n += 1 }
                        }
                    }
                    blurred[gy * gw + gx] = sum / n
                }
            }
            cells = blurred
        }
        
        // Smooth over time (60 Hz frames): the grid ~50 ms, the scene depth ~150 ms.
        let first = version == 0
        for i in grid.indices { grid[i] = first ? cells[i] : grid[i] + 0.3 * (cells[i] - grid[i]) }
        sceneDepth = first ? measuredScene : sceneDepth + 0.1 * (measuredScene - sceneDepth)
        version += 1
        
        let packed = grid.map { Float16($0) }
        // Full resolution for occlusion (ARKit's smoothed depth is already filtered over time).
        var full = [Float16](repeating: 0, count: w * h)
        for y in 0..<h {
            let row = (depthBase + y * depthRow).assumingMemoryBound(to: Float32.self)
            for x in 0..<w { full[y * w + x] = Float16(row[x]) }
        }
        lock.lock()
        result = Result(grid: packed, full: full, fullW: w, fullH: h, sceneDepth: sceneDepth, version: version)
        lock.unlock()
    }
}
