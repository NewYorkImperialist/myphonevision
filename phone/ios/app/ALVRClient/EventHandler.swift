//
//  EventHandler.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 26.02.2024.
//

import UIKit
import simd

class EventHandler: ObservableObject {
    enum ConnectionState {
        case disconnected
        case connected
        // case connecting
    }
    
    static let shared = EventHandler()
    
    @Published var connectionState: ConnectionState = .disconnected
    @Published var hostname: String = ""
    @Published var ipAddr: String = ""
    
    var alvrInitialized = false
    var streamingActive = false
    private var pollingStarted = false
    private var lastBatteryStateUpdateTime: Int64 = 0
    private var worldTracker: WorldTracker? = nil
    private var alvrEvent: AlvrEvent = AlvrEvent()
    /// Position in the per-sample rotation tag sawtooth (see sendTracking).
    private var tagIndex = 0
    /// Eye views (head space) last sent to ALVR; nil = send them on the next tracking update.
    private var sentViewsKey: [Float]? = nil
    /// How far ahead to predict the head: ALVR's pipeline latency, learned from when
    /// frames reach the screen (see updatePrediction). v21's C API doesn't expose it.
    private(set) var predictionNs: UInt64 = 50_000_000
    
    var delegate: EventHandlerDelegate? = nil
    
    /// Initialize alvr client but don't allow connecting
    func initialize(size: CGSize) {
        if pollingStarted { return }   // the drawable can resize; ALVR is set up once
        let refreshRates: [Float] = [60, 72, 90, 120]   // the stream rate; the display runs at 120 Hz with reprojection
        let width = UInt32(size.width)
        let oneViewWidth = (width / 2)
        let height = UInt32(size.height)
        var capabilities = AlvrClientCapabilities()
        capabilities.default_view_width = oneViewWidth
        capabilities.default_view_height = height
        // Largest per-eye size the server may send (4096 wide in total for the decoder).
        capabilities.max_view_width = max(oneViewWidth, 2048)
        capabilities.max_view_height = max(height, 2048)
        capabilities.refresh_rates_count = UInt64(refreshRates.count)
        capabilities.foveated_encoding = false
        capabilities.encoder_high_profile = true
        capabilities.encoder_10_bits = true
        capabilities.encoder_av1 = false
        capabilities.prefer_10bit = false   // the lens pass reads 8-bit NV12
        capabilities.preferred_encoding_gamma = 1.0
        capabilities.prefer_hdr = false
        // The pointer must stay valid while alvr_initialize copies the list.
        refreshRates.withUnsafeBufferPointer { rates in
            capabilities.refresh_rates = rates.baseAddress
            alvr_initialize(capabilities)
        }
        if !pollingStarted {
            pollingStarted = true
            startPollingThread()
        }
        
        print("ALVR initialized.")
    }
    
    /// Allow connection (ALVR asks for a key frame itself once the decoder is set up)
    func start() {
        alvr_resume()
    }
    
    /// Recreate world tracking with new params
    func setWorldTrackingParams(isTrackOrientation: Bool, isTrackPosition: Bool) {
        worldTracker?.stop()
        worldTracker = .init(isTrackOrientation: isTrackOrientation, isTrackPosition: isTrackPosition)
        worldTracker?.start()
    }

    /// Recentered head pose from ARKit, or nil before tracking starts.
    func headToWorld() -> simd_float4x4? {
        return worldTracker?.headToWorld()
    }

    /// Head pose predicted to `time` (CACurrentMediaTime clock).
    func headToWorld(at time: Double) -> simd_float4x4? {
        return worldTracker?.headToWorld(at: time)
    }

    func recenter() {
        worldTracker?.recenter()
    }
    
    private func parseMessage(_ message: String) {
        let lines = message.components(separatedBy: "\n")
        for line in lines {
            let keyValuePair = line.split(separator: ":")
            if keyValuePair.count == 2 {
                let key = keyValuePair[0].trimmingCharacters(in: .whitespaces)
                let value = keyValuePair[1].trimmingCharacters(in: .whitespaces)
                        if key == "hostname" {
                            updateHostname(value)
                        } else if key == "IP" {
                            updateIp(value)
                        }
            }
        }
    }
    
    private func updateHostname(_ newHostname: String) {
        DispatchQueue.main.async {
            self.hostname = newHostname
        }
    }

    private func updateIp(_ newIp: String) {
        DispatchQueue.main.async {
            self.ipAddr = newIp
        }
    }
    
    private func updateConnectionState(_ newState: ConnectionState) {
        DispatchQueue.main.async {
            self.connectionState = newState
        }
    }
    
    /// Poll all alvr events
    func pollEvents() {
        let res = alvr_poll_event(&alvrEvent)
        if res {
            // print(alvrEvent.tag)
            switch UInt32(alvrEvent.tag) {
            case ALVR_EVENT_HUD_MESSAGE_UPDATED.rawValue:
                print("hud message updated")
                let hudMessageBuffer = UnsafeMutableBufferPointer<CChar>.allocate(capacity: 1024)
                alvr_hud_message(hudMessageBuffer.baseAddress)
                
                let message = String(cString: hudMessageBuffer.baseAddress!, encoding: .utf8)!
                parseMessage(message)
                print(message)
                
                hudMessageBuffer.deallocate()
            case ALVR_EVENT_STREAMING_STARTED.rawValue:
                updateConnectionState(.connected)
                
                print("streaming started: \(alvrEvent.STREAMING_STARTED)")
                sentViewsKey = nil   // a new connection needs the eye views again
                delegate?.updateStreamingState(isStarted: true)
                streamingActive = true
                alvrInitialized = true
            case ALVR_EVENT_STREAMING_STOPPED.rawValue:
                updateConnectionState(.disconnected)
                
                print("streaming stopped")
                alvrInitialized = false
                streamingActive = false
                delegate?.updateStreamingState(isStarted: false)
            case ALVR_EVENT_HAPTICS.rawValue:
                print("haptics: \(alvrEvent.HAPTICS)")
            case ALVR_EVENT_DECODER_CONFIG.rawValue:
                streamingActive = true
                print("create decoder: \(alvrEvent.DECODER_CONFIG)")
                delegate?.createDecoder()
            case ALVR_EVENT_REAL_TIME_CONFIG.rawValue:
                break   // not implemented in ALVR yet
            default:
                print("what")
            }
        } else {
            usleep(1000)
        }
    }

    /// One thread that keeps draining ALVR events (started once).
    func startPollingThread() {
        let thread = Thread { while true { EventHandler.shared.pollEvents() } }
        thread.name = "ALVR events"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Send the head pose to ALVR. Call once per display refresh while streaming.
    /// v21 takes the head as the /user/head device and the two eye views separately,
    /// in head space; the eye views are resent only when the IPD or lens FOV changes.
    func sendTracking() {
        // Ask for a frame predicted for when it will be on screen (the measured
        // pipeline latency); our own extrapolation is capped at 50 ms of that.
        let predictionNs = self.predictionNs
        let targetNs = Clock.nowNs() &+ predictionNs
        guard alvrInitialized,
              let head = worldTracker?.headToWorld(at: CACurrentMediaTime() + Double(predictionNs) / 1e9) else { return }
        let settings = VRSettings.current
        let fovs = settings.eyeFovTangents()
        let halfIpd = settings.ipdMm / 2000

        let viewsKey = [settings.ipdMm] + fovs.flatMap { [$0.x, $0.y, $0.z, $0.w] }
        if viewsKey != sentViewsKey {
            func view(_ side: Float, _ fov: SIMD4<Float>) -> AlvrViewParams {
                return AlvrViewParams(pose: AlvrPose(orientation: AlvrQuat(x: 0, y: 0, z: 0, w: 1),
                                                     position: (side * halfIpd, 0, 0)),
                                      fov: AlvrFov(left: atan(fov.x), right: atan(fov.y), up: atan(fov.z), down: atan(fov.w)))
            }
            let views = [view(-1, fovs[0]), view(1, fovs[1])]
            views.withUnsafeBufferPointer { alvr_send_view_params($0.baseAddress) }
            sentViewsKey = viewsKey
        }

        // Make every sample's rotation unique. The server finds the sample a frame was
        // rendered with by closest rotation among its last 360 (PoseHistory::
        // GetBestPoseMatch, oldest on ties), and a still head sends identical rotations
        // (120 Hz sends, 60 Hz ARKit), so frames came back seconds old. A tiny yaw
        // sawtooth (2e-6 rad steps, 400-sample period, at most 0.05°) gives an exact
        // match. Reprojection removes it: frames return their rendered pose, tag included.
        tagIndex = (tagIndex + 1) % 400
        let tag = simd_quatf(angle: Float(tagIndex) * 2e-6, axis: SIMD3<Float>(0, 1, 0))
        let q = simd_normalize(simd_quatf(head.rotation3x3) * tag)
        let p = head.translation
        var motion = AlvrDeviceMotion(
            device_id: MetalView.Coordinator.deviceIdHead,
            pose: AlvrPose(orientation: AlvrQuat(x: q.imag.x, y: q.imag.y, z: q.imag.z, w: q.real), position: (p.x, p.y, p.z)),
            linear_velocity: (0, 0, 0),
            angular_velocity: (0, 0, 0))
        // The target time doubles as the poll timestamp: frames come back tagged with it.
        alvr_send_tracking(targetNs, &motion, 1, nil, nil)
        Renderer.shared?.lastRequestedTimestamp = targetNs

        // Send battery state every 30 secs
        if Int64.getCurrentMillis() - lastBatteryStateUpdateTime > 1000 * 30 {
            lastBatteryStateUpdateTime = Int64.getCurrentMillis()
            UIDevice.current.isBatteryMonitoringEnabled = true
            alvr_send_battery(MetalView.Coordinator.deviceIdHead, UIDevice.current.batteryLevel, UIDevice.current.batteryState == .charging)
        }
    }

    /// A frame requested for `frameTimestampNs` reaches the screen at `displayNs`:
    /// nudge the prediction toward the real latency (10% per frame, 0 to 100 ms).
    /// The server tags frames with its best rotation match from ~3 s of tracking
    /// history (oldest on ties), so with a still head the timestamp can be seconds
    /// old. Skip errors over 100 ms: those are stale matches, not latency.
    func updatePrediction(frameTimestampNs: UInt64, displayNs: UInt64) {
        let errorNs = Int64(bitPattern: displayNs &- frameTimestampNs)
        guard abs(errorNs) < 100_000_000 else { return }
        let next = Int64(predictionNs) + errorNs / 10
        predictionNs = UInt64(min(max(next, 0), 100_000_000))
    }
}
