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
        capabilities.refresh_rates_count = Int32(refreshRates.count)
        capabilities.external_decoder = true
        capabilities.foveated_encoding = false
        capabilities.encoder_high_profile = true
        capabilities.encoder_10_bits = true
        capabilities.encoder_av1 = false
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
    
    /// Allow connection and request frames
    func start() {
        alvr_resume()
        alvr_request_idr()
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

    func latestCameraFrame() -> WorldTracker.CameraFrame? {
        return worldTracker?.latestCameraFrame()
    }

    func smoothedDepth() -> DepthSmoother.Result? {
        return worldTracker?.smoothedDepth()
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
                delegate?.updateStreamingState(isStarted: true)
                if !streamingActive {
                    streamingActive = true
                    alvr_request_idr()
                }
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
            case ALVR_EVENT_FRAME_READY.rawValue:
                // print("frame ready")
                if connectionState == .connected {
                    delegate?.updateFrame()

                    // Send battery state every 30 secs
                    if Int64.getCurrentMillis() - lastBatteryStateUpdateTime > 1000 * 30 {
                        lastBatteryStateUpdateTime = Int64.getCurrentMillis()
                        UIDevice.current.isBatteryMonitoringEnabled = true
                        print("Update battery state: \(UIDevice.current.batteryLevel) / 1.0 | Is charging: \(UIDevice.current.batteryState == .charging)")
                        alvr_send_battery(MetalView.Coordinator.deviceIdHead, UIDevice.current.batteryLevel, UIDevice.current.batteryState == .charging)
                    }
                }
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

    /// Send the head pose to ALVR as two eye views. Call once per display refresh
    /// while streaming. ALVR derives the head itself (left eye's orientation at the
    /// midpoint of the eyes), and resends the FOV whenever the eye distance changes.
    func sendTracking() {
        // Ask for a frame predicted for when it will be on screen (ALVR's measured
        // pipeline latency); our own extrapolation is capped at 50 ms of that.
        let predictionNs = alvr_get_head_prediction_offset_ns()
        let targetNs = Clock.nowNs() &+ predictionNs
        guard alvrInitialized,
              let head = worldTracker?.headToWorld(at: CACurrentMediaTime() + Double(predictionNs) / 1e9) else { return }
        let settings = VRSettings.current
        let fovs = settings.eyeFovTangents()
        let q = simd_quatf(head.rotation3x3)
        let orientation = AlvrQuat(x: q.imag.x, y: q.imag.y, z: q.imag.z, w: q.real)
        let halfIpd = settings.ipdMm / 2000

        func view(_ side: Float, _ fov: SIMD4<Float>) -> AlvrViewParams {
            let p = head.translation + side * halfIpd * head.rightAxis
            return AlvrViewParams(pose: AlvrPose(orientation: orientation, position: (p.x, p.y, p.z)),
                                  fov: AlvrFov(left: atan(fov.x), right: atan(fov.y), up: atan(fov.z), down: atan(fov.w)))
        }
        let views = [view(-1, fovs[0]), view(1, fovs[1])]

        var noMotions = AlvrDeviceMotion()
        views.withUnsafeBufferPointer { viewsPtr in
            alvr_send_tracking(targetNs, viewsPtr.baseAddress, &noMotions, 0, nil, nil)
        }
        Renderer.shared?.lastRequestedTimestamp = targetNs
    }
}
