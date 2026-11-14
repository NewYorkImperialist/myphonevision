//
//  Renderer.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 23.02.2024.
//

import SwiftUI
import VideoToolbox
import MetalKit
import CoreMotion
import Spatial
import ARKit

// TODO: Move to inside Renderer
let globalPixelFormat: MTLPixelFormat = .bgra8Unorm_srgb

final class Renderer {
    struct QueuedFrame {
        let imageBuffer: CVImageBuffer
        let timestamp: UInt64
        /// Eye poses and FOVs the frame was rendered for, from alvr_report_compositor_start
        /// when the frame is first shown. Zero until then (the lens pass falls back).
        var viewParams: [AlvrViewParams] = [AlvrViewParams(), AlvrViewParams()]
    }
    
    static var shared: Renderer? = nil
    
    private let metalDevice: MTLDevice
    private let metalCommandQueue: MTLCommandQueue
    
    let inFlightSemaphore = DispatchSemaphore(value: 3)
    
    var deviceAnchorsLock = NSObject()
    var deviceAnchorsQueue = [UInt64]()
    var deviceAnchorsDictionary = [UInt64: simd_float4x4]()
    var metalTextureCache: CVMetalTextureCache!
    var videoFramePipelineState: MTLRenderPipelineState!
    var lastIpd: Float = -1
    
    var frameQueueLock = NSObject()
    
    var frameQueue = [QueuedFrame]()
    var frameQueueLastTimestamp: UInt64 = 0
    var frameQueueLastImageBuffer: CVImageBuffer? = nil
    var lastQueuedFrame: QueuedFrame? = nil
    var lastRequestedTimestamp: UInt64 = 0
    var lastSubmittedTimestamp: UInt64 = 0
    
    var framesRendered: Int = 0
    var framesSinceLastIDR: Int = 0
    var framesSinceLastDecode: Int = 0
    
    var vtDecompressionSession: VTDecompressionSession? = nil
    var videoFormat: CMFormatDescription? = nil
    
    var lastFps: Int = 0
    var currentFps: Int = 0
    var lastFpsUpdateTime: Int64 = 0
    
    init(metalDevice: MTLDevice) {
        guard let metalCommandQueue = metalDevice.makeCommandQueue() else { fatalError("Can't create command queue.") }
        
        self.metalDevice = metalDevice
        self.metalCommandQueue = metalCommandQueue
        
        if CVMetalTextureCacheCreate(nil, nil, metalDevice, nil, &metalTextureCache) != 0 {
            fatalError("CVMetalTextureCacheCreate")
        }
    }
    
    func draw(drawable: CAMetalDrawable, renderPassDescriptor: MTLRenderPassDescriptor) {
        let commandBuffer = metalCommandQueue.makeCommandBuffer()!
        
        framesRendered += 1
        
        var queuedFrame: QueuedFrame? = nil
        var isNewFrame = false
        if true {
            let startPollTime = CACurrentMediaTime()
            while true {
                sched_yield()
                // Show the newest decoded frame; older ones in the queue are already late.
                objc_sync_enter(frameQueueLock)
                queuedFrame = frameQueue.last
                frameQueue.removeAll()
                objc_sync_exit(frameQueueLock)
                if queuedFrame != nil {
                    isNewFrame = true
                    break
                }

                // No new frame: show the last one again; reprojection turns it to the current head.
                if lastQueuedFrame != nil {
                    queuedFrame = lastQueuedFrame
                    break
                }
                
                if CACurrentMediaTime() - startPollTime > 0.002 {
                    break
                }
            }
        }
        
        if isNewFrame, var frame = queuedFrame {
            // ALVR returns the eye poses this frame was rendered for; if it has none,
            // keep the previous frame's.
            var metadata = AlvrVideoFrameMetadata()
            if alvr_report_compositor_start(frame.timestamp, &metadata) {
                frame.viewParams = [metadata.view_params.0, metadata.view_params.1]
            } else if let previous = lastQueuedFrame {
                frame.viewParams = previous.viewParams
            }
            let vsyncNs = UInt64(1e9 / Double(VRSettings.current.displayHz))
            EventHandler.shared.updatePrediction(frameTimestampNs: frame.timestamp, displayNs: Clock.nowNs() &+ vsyncNs)
            queuedFrame = frame
            lastQueuedFrame = frame
        }
        
        if queuedFrame != nil {
            objc_sync_enter(frameQueueLock)
            framesSinceLastDecode += 1
            objc_sync_exit(frameQueueLock)
            
            let vsyncTime = 1.0 / Double(VRSettings.current.displayHz)
            let vsyncTimeNs = UInt64(vsyncTime * Double(NSEC_PER_SEC))
            // let framePreviouslyPredictedPose = queuedFrame != nil ? lookupDeviceAnchorFor(timestamp: queuedFrame!.timestamp) : nil
            
            // Report every new frame shown, even if its timestamp repeats: the server
            // tags frames by guessing which tracking sample SteamVR rendered with
            // (closest rotation, oldest on ties), so a still head gives many frames one
            // old timestamp. Skipping repeats left ALVR seeing ~0.1 fps.
            let semaphore = inFlightSemaphore
            let reportSubmit = isNewFrame
            commandBuffer.addCompletedHandler { (_ commandBuffer)-> Swift.Void in
                if reportSubmit, let frame = queuedFrame {
                    // vsync_queue_ns: time from submit to display, about one refresh.
                    alvr_report_submit(frame.timestamp, vsyncTimeNs)
                    self.lastSubmittedTimestamp = frame.timestamp
                }
                semaphore.signal()
            }
            
            renderStreamingFrame(renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer, drawable: drawable, queuedFrame: queuedFrame!)
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
    
    /// When the frame being drawn now reaches the screen: about one refresh from now.
    static func nextDisplayTime() -> Double {
        return CACurrentMediaTime() + 1.0 / Double(VRSettings.current.displayHz)
    }

    // ---- Test mode: no server needed ----
    // Renders the room into a side-by-side eye texture at a (optionally delayed) pose,
    // the way the PC renders a stream frame, then shows it through the same lens pass
    // and reprojection as the stream.
    var testMode = false
    private var testEyesPipelineState: MTLRenderPipelineState?
    private var frameRGBPipelineState: MTLRenderPipelineState?
    private var testEyesTexture: MTLTexture?
    private var poseHistory: [(time: Double, head: simd_float4x4)] = []

    func drawTestScene(drawable: CAMetalDrawable, renderPassDescriptor: MTLRenderPassDescriptor) {
        if testEyesPipelineState == nil {
            testEyesPipelineState = try! Renderer.buildRenderPipelineWithDevice(device: metalDevice, fragment: "vrTestEyes")
            frameRGBPipelineState = try! Renderer.buildRenderPipelineWithDevice(device: metalDevice, fragment: "vrStreamRGB")
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: globalPixelFormat, width: 2048, height: 1024, mipmapped: false)
            desc.usage = [.renderTarget, .shaderRead]
            desc.storageMode = .private
            testEyesTexture = metalDevice.makeTexture(descriptor: desc)
        }
        guard let commandBuffer = metalCommandQueue.makeCommandBuffer() else { return }

        let settings = VRSettings.current
        let now = CACurrentMediaTime()
        let displayHead = EventHandler.shared.headToWorld(at: Renderer.nextDisplayTime()) ?? matrix_identity_float4x4
        poseHistory.append((now, displayHead))
        poseHistory.removeAll { $0.time < now - 0.5 }
        let renderTime = now - Double(settings.latencyMs) / 1000
        let renderedHead = poseHistory.last(where: { $0.time <= renderTime })?.head ?? poseHistory[0].head

        var displayUniforms = Renderer.makeVRUniforms(drawable: drawable, head: displayHead)
        var renderUniforms = displayUniforms
        renderUniforms.headToWorld = renderedHead
        var frameUniforms = Renderer.makeFrameUniforms(renderedHead: renderedHead, displayHead: displayHead,
                                                       fovTan: settings.eyeFovTangents())

        // Pass 1: "the PC" renders both eyes at the delayed pose.
        let eyesPass = MTLRenderPassDescriptor()
        eyesPass.colorAttachments[0].texture = testEyesTexture
        eyesPass.colorAttachments[0].loadAction = .dontCare
        eyesPass.colorAttachments[0].storeAction = .store
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: eyesPass) {
            encoder.label = "Test eyes"
            encoder.setRenderPipelineState(testEyesPipelineState!)
            encoder.setFragmentBytes(&renderUniforms, length: MemoryLayout<VRUniforms>.stride, index: 0)
            encoder.setFragmentBytes(&frameUniforms, length: MemoryLayout<VRFrameUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 1)
            encoder.endEncoding()
        }
        // Pass 2: the phone shows it through the lenses, reprojected to the current head.
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            encoder.label = "Lens pass (test)"
            encoder.setRenderPipelineState(frameRGBPipelineState!)
            encoder.setFragmentBytes(&displayUniforms, length: MemoryLayout<VRUniforms>.stride, index: 0)
            encoder.setFragmentBytes(&frameUniforms, length: MemoryLayout<VRFrameUniforms>.stride, index: 1)
            encoder.setFragmentTexture(testEyesTexture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 1)
            encoder.endEncoding()
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    static func makeVRUniforms(drawable: CAMetalDrawable, head: simd_float4x4) -> VRUniforms {
        let s = VRSettings.current
        let w = Float(drawable.texture.width)
        let h = Float(drawable.texture.height)
        return VRUniforms(
            headToWorld: head,
            lens: SIMD4<Float>(s.k1, s.k2, s.screenToLensMm, s.ipdMm),
            screen: SIMD4<Float>(w, h, VRSettings.screenWidthMm / max(w, h), s.lensYOffsetMm),
            misc: SIMD4<Float>(Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 1000)), 0, 0, 0))
    }

    /// Reprojection rotates each eye ray from the display-time head into the head the
    /// frame was rendered for (rotation only). Off, or with no rendered pose, it's identity.
    static func makeFrameUniforms(renderedHead: simd_float4x4?, displayHead: simd_float4x4,
                                  fovTan: [SIMD4<Float>]) -> VRFrameUniforms {
        var reproject = matrix_identity_float4x4
        if VRSettings.current.reprojection > 0.5, let rendered = renderedHead {
            reproject = simd_transpose(rendered.rotationOnly) * displayHead.rotationOnly
        }
        return VRFrameUniforms(reproject: reproject, fovTan: (fovTan[0], fovTan[1]))
    }

    func updateStreamingState(isStarted: Bool) {
        if isStarted {
            videoFramePipelineState = try! Renderer.buildRenderPipelineWithDevice(device: metalDevice, fragment: "vrStreamYUV")
            framesSinceLastIDR = 0
            framesSinceLastDecode = 0
            
            lastIpd = 0.063 // What is it
        } else {
            idrRequested = false
            objc_sync_enter(frameQueueLock)
            frameQueue.removeAll()
            lastQueuedFrame = nil
            objc_sync_exit(frameQueueLock)
            vtDecompressionSession = nil
            videoFormat = nil
            lastRequestedTimestamp = 0
            lastSubmittedTimestamp = 0
            framesRendered = 0
            framesSinceLastIDR = 0
            framesSinceLastDecode = 0
            timeLastAlvrEvent = CACurrentMediaTime()
            timeLastFrameSent = CACurrentMediaTime()
            
            lastIpd = -1
        }
    }
    
    var timeLastSentPeriodicUpdatedValues: Double = 0.0
        var timeLastSentMdnsBroadcast: Double = 0.0
        var timeLastAlvrEvent: Double = 0.0
        var timeLastFrameGot: Double = 0.0
        var timeLastFrameSent: Double = 0.0
        var timeLastFrameDecoded: Double = 0.0
        var numberOfEventThreadRestarts: Int = 0
    
    var stutterSampleStart = 0.0
        var stutterEventsCounted = 0
        var lastStutterTime = 0.0
        var awdlAlertPresented = false
        var audioIsOff = false
    
    var renderStarted = false
    
    func setIsStarted(isStarted: Bool) {
        self.renderStarted = isStarted
    }
    
    /// Set from any thread to get a key frame: the next NAL is refused, and ALVR
    /// answers a refused NAL by requesting an IDR and dropping frames until it arrives.
    var idrRequested = false

    func requestIdr() {
        idrRequested = true
    }

    /// ALVR calls this on its video thread for every frame (set up in createDecoder).
    /// Returns false if the frame wasn't submitted to the decoder.
    static let decoderInputCallback: @convention(c) (AlvrVideoFrameData) -> Bool = { frame in
        guard let renderer = Renderer.shared, let buffer = frame.buffer_ptr else { return false }
        // The buffer is only valid during this call.
        let nal = Data(bytes: buffer, count: Int(frame.buffer_size))
        return renderer.handleNal(timestamp: frame.timestamp_ns, nal: nal)
    }

    /// Decode one frame; when decoded, add it to the frameQueue.
    func handleNal(timestamp: UInt64, nal: Data) -> Bool {
        timeLastFrameGot = CACurrentMediaTime()
        guard let vtDecompressionSession = vtDecompressionSession, let videoFormat = videoFormat else {
            return false
        }

        objc_sync_enter(frameQueueLock)
        framesSinceLastIDR += 1

        // Refuse a frame only after a real decoder error. Never for looking "old": the
        // timestamp is the server's guess of the tracking sample the frame was rendered
        // with (closest rotation in ~3 s of history, oldest on ties), so with a still
        // head it can be seconds old. Refusing those forced an IDR every few seconds.
        if idrRequested {
            print("Decoder error: asking for a key frame", framesSinceLastDecode, framesSinceLastIDR)
            // Refusing the frame makes ALVR request an IDR to resume the video feed
            idrRequested = false
            framesSinceLastIDR = 0
            framesSinceLastDecode = 0
            objc_sync_exit(frameQueueLock)
            return false
        }
        objc_sync_exit(frameQueueLock)

        let startedDecodeTime = CACurrentMediaTime()

        return VideoHandler.feedVideoIntoDecoder(decompressionSession: vtDecompressionSession, nals: nal, timestamp: timestamp, videoFormat: videoFormat) { [self] imageBuffer in
            guard let imageBuffer = imageBuffer else {
                return
            }

            if (CACurrentMediaTime() - startedDecodeTime > Double(50*MSEC_PER_SEC)) {
                print("Handle decode overrun!", CACurrentMediaTime() - startedDecodeTime, framesSinceLastDecode, framesSinceLastIDR)
                requestIdr()
                return
            }

            timeLastFrameDecoded = CACurrentMediaTime()

            objc_sync_enter(frameQueueLock)
            framesSinceLastDecode = 0
            alvr_report_frame_decoded(timestamp)

            frameQueue.append(QueuedFrame(imageBuffer: imageBuffer, timestamp: timestamp))
            if frameQueue.count > 3 {
                frameQueue.removeFirst()
            }
            frameQueueLastTimestamp = timestamp
            frameQueueLastImageBuffer = imageBuffer
            timeLastFrameSent = CACurrentMediaTime()
            objc_sync_exit(frameQueueLock)
        }
    }

    func createDecoder() {
        // ALVR sends the config once per connection; ignore repeats.
        // TODO: Switching from H264 -> HEVC at runtime?
        if vtDecompressionSession != nil {
            return
        }

        // The codec config: SPS + PPS (H.264) or VPS + SPS + PPS (HEVC), Annex B.
        let configSize = Int(alvr_get_decoder_config(nil))
        guard configSize > 5 else {
            print("create decoder: no decoder config")
            return
        }
        var configBytes = [CChar](repeating: 0, count: configSize)
        alvr_get_decoder_config(&configBytes)
        let nal = Data(bytes: configBytes, count: configSize)
        NSLog("%@", nal as NSData)
        if (nal[3] == 0x01 && nal[4] & 0x1f == H264_NAL_TYPE_SPS) || (nal[2] == 0x01 && nal[3] & 0x1f == H264_NAL_TYPE_SPS) {
            (vtDecompressionSession, videoFormat) = VideoHandler.createVideoDecoder(initialNals: nal, codec: H264_NAL_TYPE_SPS)
        } else if (nal[3] == 0x01 && (nal[4] & 0x7E) >> 1 == HEVC_NAL_TYPE_VPS) || (nal[2] == 0x01 && (nal[3] & 0x7E) >> 1 == HEVC_NAL_TYPE_VPS) {
            // The NAL unit type is 32 (VPS)
            (vtDecompressionSession, videoFormat) = VideoHandler.createVideoDecoder(initialNals: nal, codec: HEVC_NAL_TYPE_VPS)
        } else {
            print("create decoder: unknown config NAL type \((nal[4] & 0x7E) >> 1)")
            return
        }

        // Start receiving frames; this also asks the server for a key frame.
        renderStarted = true
        alvr_set_decoder_input_callback(nil, Renderer.decoderInputCallback)
    }
    
    func updateFrameStats() {
        if Int64.getCurrentMillis() - lastFpsUpdateTime > 1000 {
            lastFpsUpdateTime = Int64.getCurrentMillis()
            
            lastFps = currentFps
            currentFps = 0
            
            print("FPS: \(lastFps)")
        }
        
        currentFps += 1
    }
    
    func processFrame(imageBuffer: CVImageBuffer) {
        //let timestamp = mach_absolute_time()
        
//        objc_sync_enter(frameQueueLock)
//        framesSinceLastDecode = 0
//        if frameQueueLastTimestamp != timestamp
//        {
//            // TODO: For some reason, really low frame rates seem to decode the wrong image for a split second?
//            // But for whatever reason this is fine at high FPS.
//            // From what I've read online, the only way to know if an H264 frame has actually completed is if
//            // the next frame is starting, so keep this around for now just in case.
//            if frameQueueLastImageBuffer != nil {
//                frameQueue.append(QueuedFrame(imageBuffer: frameQueueLastImageBuffer!, timestamp: frameQueueLastTimestamp))
//                //frameQueue.append(QueuedFrame(imageBuffer: imageBuffer, timestamp: timestamp))
//            }
//            else {
//                frameQueue.append(QueuedFrame(imageBuffer: imageBuffer, timestamp: timestamp))
//            }
//            if frameQueue.count > 2 {
//                frameQueue.removeFirst()
//            }
//            
//            //print("queue: \(frameQueueLastTimestamp) -> \(timestamp), \(test)")
//            
//            frameQueueLastTimestamp = timestamp
//            frameQueueLastImageBuffer = imageBuffer
//        }
        
        // Pull the very last imageBuffer for a given timestamp
//        if frameQueueLastTimestamp == timestamp {
//             frameQueueLastImageBuffer = imageBuffer
//        }
//        
//        objc_sync_exit(frameQueueLock)
    }
    
    func renderStreamingFrame(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer, drawable: CAMetalDrawable, queuedFrame: QueuedFrame) {
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            fatalError("Failed to create render encoder")
        }
        
        renderEncoder.label = "Lens pass (stream)"
        renderEncoder.setRenderPipelineState(videoFramePipelineState)

        // The frame comes back with the eye poses and FOVs it was rendered for (the head
        // sendTracking sent for its timestamp, plus the eye views). Fall back to our own
        // FOV if they're unset.
        let displayHead = EventHandler.shared.headToWorld(at: Renderer.nextDisplayTime()) ?? matrix_identity_float4x4
        let views = queuedFrame.viewParams
        let o = views[0].pose.orientation
        let renderedQuat = simd_quatf(ix: o.x, iy: o.y, iz: o.z, r: o.w)
        let renderedHead: simd_float4x4? = simd_length(renderedQuat.vector) > 0.5 ? simd_float4x4(simd_normalize(renderedQuat)) : nil
        var fovTan = views.map { SIMD4<Float>(tan($0.fov.left), tan($0.fov.right), tan($0.fov.up), tan($0.fov.down)) }
        if fovTan.contains(where: { !($0.y > $0.x && $0.z > $0.w) }) {
            fovTan = VRSettings.current.eyeFovTangents()
        }
        var displayUniforms = Renderer.makeVRUniforms(drawable: drawable, head: displayHead)
        var frameUniforms = Renderer.makeFrameUniforms(renderedHead: renderedHead, displayHead: displayHead, fovTan: fovTan)
        renderEncoder.setFragmentBytes(&displayUniforms, length: MemoryLayout<VRUniforms>.stride, index: 0)
        renderEncoder.setFragmentBytes(&frameUniforms, length: MemoryLayout<VRFrameUniforms>.stride, index: 1)
        
        let pixelBuffer = queuedFrame.imageBuffer
        
        for i in 0...1 {
            var textureOut: CVMetalTexture! = nil
            var err: OSStatus = 0
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            if i == 0 {
                err = CVMetalTextureCacheCreateTextureFromImage(
                    nil, metalTextureCache, pixelBuffer, nil, .r8Unorm,
                    width, height, 0, &textureOut);
            } else {
                err = CVMetalTextureCacheCreateTextureFromImage(
                    nil, metalTextureCache, pixelBuffer, nil, .rg8Unorm,
                    width/2, height/2, 1, &textureOut);
            }
            if err != 0 {
                fatalError("CVMetalTextureCacheCreateTextureFromImage \(err)")
            }
            guard let metalTexture = CVMetalTextureGetTexture(textureOut) else {
                fatalError("CVMetalTextureCacheCreateTextureFromImage")
            }
            
            renderEncoder.setFragmentTexture(metalTexture, index: i)
        }
        
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 1)
        renderEncoder.endEncoding()
    }
    
    /// Build a render state pipeline object
    private class func buildRenderPipelineWithDevice(device: MTLDevice, fragment: String = "displayTexture") throws -> MTLRenderPipelineState {
        let library = device.makeDefaultLibrary()

        let vertexFunction = library?.makeFunction(name: "mapTexture")
        let fragmentFunction = library?.makeFunction(name: fragment)

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "RenderPipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = globalPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = .invalid
            
        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
}
