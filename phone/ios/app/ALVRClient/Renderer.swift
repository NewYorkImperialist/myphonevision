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
        /// When the frame's data reached the phone (Clock.nowNs).
        let arrivalNs: UInt64
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
            // A Linux server can't tell which pose a frame was rendered with (its Vulkan
            // layer looks for function names that SteamVR's stripped vrcompositor
            // lacks), so it tags every frame with an arbitrary sample up to 3 s old.
            // SteamVR renders with its newest pose, so if the tag is far from the pose
            // we sent just before the frame arrived, reproject from that pose instead.
            // FOV still comes from the metadata.
            var poseTimestamp = frame.timestamp
            if let sent = EventHandler.shared.sentPose(atSendTime: frame.arrivalNs &- EventHandler.renderLeadNs),
               abs(Int64(bitPattern: frame.timestamp &- sent.targetNs)) > 150_000_000 {
                frame.viewParams[0].pose.orientation = sent.orientation
                frame.viewParams[1].pose.orientation = sent.orientation
                poseTimestamp = sent.targetNs
            }
            let vsyncNs = UInt64(1e9 / Double(VRSettings.current.displayHz))
            EventHandler.shared.updatePrediction(frameTimestampNs: poseTimestamp, displayNs: Clock.nowNs() &+ vsyncNs)
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
            
            prepareCamera(commandBuffer: commandBuffer)
            renderStreamingFrame(renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer, drawable: drawable, queuedFrame: queuedFrame!)
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
    
    // ---- AR passthrough ----
    private lazy var placeholderTexture: MTLTexture = {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        return metalDevice.makeTexture(descriptor: desc)!
    }()

    /// Camera uniforms and Y/CbCr textures for the latest ARKit image, bound at
    /// fragment buffer 2 and textures 2-3. With passthrough off (or no image yet)
    /// the shader ignores them. The CVMetalTextures are kept until the GPU is done.
    func bindCamera(encoder: MTLRenderCommandEncoder, commandBuffer: MTLCommandBuffer, displayHead: simd_float4x4) {
        let s = VRSettings.current
        var c = VRCameraUniforms()
        c.key = SIMD4<Float>(s.keyMode, s.keyTolerance, 0.05, 0)
        var luma: MTLTexture = placeholderTexture
        var chroma: MTLTexture = placeholderTexture
        var depth: MTLTexture = placeholderTexture
        var depthFull: MTLTexture = placeholderTexture
        var personMatte: MTLTexture = placeholderTexture
        var personDepthTex: MTLTexture = placeholderTexture
        if s.passthrough > 0.5, let cam = EventHandler.shared.latestCameraFrame(),
           let y = makePlaneTexture(cam.image, plane: 0, format: .r8Unorm),
           let cbcr = makePlaneTexture(cam.image, plane: 1, format: .rg8Unorm) {
            // cameraToHead maps head coordinates into camera coordinates (see WorldTracker).
            let headInCamera = cam.cameraToHead
            c.headToCamera = headInCamera.rotationOnly * simd_transpose(cam.headAtCapture.rotationOnly) * displayHead.rotationOnly
            let k = cam.intrinsics
            c.intrinsics = SIMD4<Float>(k.columns.0.x, k.columns.1.y, k.columns.2.x, k.columns.2.y)
            c.imageSize = SIMD4<Float>(cam.imageSize.x, cam.imageSize.y, 1.5, 1)
            c.eyeCenter = SIMD4<Float>(headInCamera.columns.3.x, headInCamera.columns.3.y, headInCamera.columns.3.z, 0)
            c.eyeRight = headInCamera.rotationOnly * SIMD4<Float>(s.ipdMm / 2000, 0, 0, 0)
            luma = CVMetalTextureGetTexture(y)!
            chroma = CVMetalTextureGetTexture(cbcr)!
            // Depth: 0 fixed 1.5 m; 1 LiDAR scene average; 2 LiDAR smoothed grid (per-pixel stereo).
            if s.lidarDepth > 0.5, let smoothed = EventHandler.shared.smoothedDepth() {
                c.imageSize.z = smoothed.sceneDepth
                if s.lidarDepth > 1.5 {
                    depth = depthGridTextures.texture(device: metalDevice, width: DepthSmoother.gridW, height: DepthSmoother.gridH,
                                                      data: smoothed.grid, version: smoothed.version)
                    c.key.w = 1
                }
            }
            // Occlusion: real things in front hide virtual content. Mode 1: ARKit's person
            // matte (prepared in prepareCamera); mode 2: full-resolution LiDAR depth.
            if s.occlusion > 1.5, let smoothed = EventHandler.shared.smoothedDepth() {
                depthFull = depthFullTextures.texture(device: metalDevice, width: smoothed.fullW, height: smoothed.fullH,
                                                      data: smoothed.full, version: smoothed.version)
                c.occlusion = SIMD4<Float>(1, s.handDistanceM, 0.04, 2)
            } else if s.occlusion > 0.5, let matte = matteTexture, let personDepth = personDepthTexture {
                personMatte = matte
                personDepthTex = personDepth
                c.occlusion = SIMD4<Float>(1, s.handDistanceM, 0.04, 1)
            }
            commandBuffer.addCompletedHandler { _ in _ = (y, cbcr) }
        }
        encoder.setFragmentBytes(&c, length: MemoryLayout<VRCameraUniforms>.stride, index: 2)
        encoder.setFragmentTexture(luma, index: 2)
        encoder.setFragmentTexture(chroma, index: 3)
        encoder.setFragmentTexture(depth, index: 4)
        encoder.setFragmentTexture(depthFull, index: 5)
        encoder.setFragmentTexture(personMatte, index: 6)
        encoder.setFragmentTexture(personDepthTex, index: 7)
    }

    // Person segmentation (ARKit's matte, refined against the camera image) for
    // "people & hands" occlusion; regenerated once per camera image.
    private lazy var matteGenerator = ARMatteGenerator(device: metalDevice, matteResolution: .half)
    private var matteTexture: MTLTexture?
    private var personDepthTexture: MTLTexture?
    private var matteFrameTime: Double = -1

    /// Call before creating any render encoder on this command buffer.
    func prepareCamera(commandBuffer: MTLCommandBuffer) {
        let s = VRSettings.current
        guard s.passthrough > 0.5, s.occlusion > 0.5, s.occlusion < 1.5,
              let cam = EventHandler.shared.latestCameraFrame(), cam.frame.segmentationBuffer != nil else {
            matteTexture = nil
            personDepthTexture = nil
            return
        }
        if cam.frame.timestamp != matteFrameTime {
            matteFrameTime = cam.frame.timestamp
            matteTexture = matteGenerator.generateMatte(from: cam.frame, commandBuffer: commandBuffer)
            personDepthTexture = matteGenerator.generateDilatedDepth(from: cam.frame, commandBuffer: commandBuffer)
        }
    }

    private let depthGridTextures = RotatingTexture()
    private let depthFullTextures = RotatingTexture()

    private func makePlaneTexture(_ buffer: CVPixelBuffer, plane: Int, format: MTLPixelFormat) -> CVMetalTexture? {
        var texture: CVMetalTexture?
        let planar = CVPixelBufferIsPlanar(buffer)   // the depth map isn't
        let width = planar ? CVPixelBufferGetWidthOfPlane(buffer, plane) : CVPixelBufferGetWidth(buffer)
        let height = planar ? CVPixelBufferGetHeightOfPlane(buffer, plane) : CVPixelBufferGetHeight(buffer)
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, metalTextureCache, buffer, nil, format, width, height, plane, &texture)
        return status == kCVReturnSuccess ? texture : nil
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
    private var testDistanceTexture: MTLTexture?   // virtual distance per pixel, for occlusion
    private var poseHistory: [(time: Double, head: simd_float4x4)] = []

    func drawTestScene(drawable: CAMetalDrawable, renderPassDescriptor: MTLRenderPassDescriptor) {
        if testEyesPipelineState == nil {
            testEyesPipelineState = try! Renderer.buildRenderPipelineWithDevice(device: metalDevice, fragment: "vrTestEyes",
                                                                                 secondColorFormat: .r16Float)
            frameRGBPipelineState = try! Renderer.buildRenderPipelineWithDevice(device: metalDevice, fragment: "vrStreamRGB")
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: globalPixelFormat, width: 2048, height: 1024, mipmapped: false)
            desc.usage = [.renderTarget, .shaderRead]
            desc.storageMode = .private
            testEyesTexture = metalDevice.makeTexture(descriptor: desc)
            desc.pixelFormat = .r16Float
            testDistanceTexture = metalDevice.makeTexture(descriptor: desc)
        }
        guard let commandBuffer = metalCommandQueue.makeCommandBuffer() else { return }
        prepareCamera(commandBuffer: commandBuffer)

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
        eyesPass.colorAttachments[1].texture = testDistanceTexture
        eyesPass.colorAttachments[1].loadAction = .dontCare
        eyesPass.colorAttachments[1].storeAction = .store
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
            encoder.setFragmentTexture(testDistanceTexture, index: 1)
            bindCamera(encoder: encoder, commandBuffer: commandBuffer, displayHead: displayHead)
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
            misc: SIMD4<Float>(Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 1000)), s.passthrough, 0, 0))
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
        let arrivalNs = Clock.nowNs()
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

            frameQueue.append(QueuedFrame(imageBuffer: imageBuffer, timestamp: timestamp, arrivalNs: arrivalNs))
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
        bindCamera(encoder: renderEncoder, commandBuffer: commandBuffer, displayHead: displayHead)
        
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
    private class func buildRenderPipelineWithDevice(device: MTLDevice, fragment: String = "displayTexture",
                                                     secondColorFormat: MTLPixelFormat? = nil) throws -> MTLRenderPipelineState {
        let library = device.makeDefaultLibrary()

        let vertexFunction = library?.makeFunction(name: "mapTexture")
        let fragmentFunction = library?.makeFunction(name: fragment)

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "RenderPipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = globalPixelFormat
        if let secondColorFormat {
            pipelineDescriptor.colorAttachments[1].pixelFormat = secondColorFormat
        }
        pipelineDescriptor.depthAttachmentPixelFormat = .invalid
            
        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
}

/// Small Float16 textures updated from the CPU, three in rotation so the CPU never
/// rewrites one that a frame still in flight is reading.
final class RotatingTexture {
    private var textures: [MTLTexture] = []
    private var version = -1
    private var index = 0
    
    func texture(device: MTLDevice, width: Int, height: Int, data: [Float16], version: Int) -> MTLTexture {
        if textures.isEmpty || textures[0].width != width || textures[0].height != height {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r16Float, width: width, height: height, mipmapped: false)
            desc.usage = .shaderRead
            textures = (0..<3).map { _ in device.makeTexture(descriptor: desc)! }
            self.version = -1
        }
        if version != self.version {
            self.version = version
            index = (index + 1) % textures.count
            data.withUnsafeBytes { bytes in
                textures[index].replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                                        withBytes: bytes.baseAddress!, bytesPerRow: width * MemoryLayout<Float16>.size)
            }
        }
        return textures[index]
    }
}
