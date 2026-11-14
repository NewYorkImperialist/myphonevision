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
        let viewParams: [AlvrViewParams]
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
        if true {
            let startPollTime = CACurrentMediaTime()
            while true {
                sched_yield()
                objc_sync_enter(frameQueueLock)
                queuedFrame = frameQueue.count > 0 ? frameQueue.removeFirst() : nil
                objc_sync_exit(frameQueueLock)
                if queuedFrame != nil {
                    lastQueuedFrame = queuedFrame
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
        
        if queuedFrame != nil && lastSubmittedTimestamp != queuedFrame!.timestamp {
            alvr_report_compositor_start(queuedFrame!.timestamp)
        }
        
        if queuedFrame != nil {
            objc_sync_enter(frameQueueLock)
            framesSinceLastDecode += 1
            objc_sync_exit(frameQueueLock)
            
            let vsyncTime = 1.0 / Double(VRSettings.current.displayHz)
            let vsyncTimeNs = UInt64(vsyncTime * Double(NSEC_PER_SEC))
            // let framePreviouslyPredictedPose = queuedFrame != nil ? lookupDeviceAnchorFor(timestamp: queuedFrame!.timestamp) : nil
            
            let semaphore = inFlightSemaphore
            commandBuffer.addCompletedHandler { (_ commandBuffer)-> Swift.Void in
                if queuedFrame != nil && self.lastSubmittedTimestamp != queuedFrame?.timestamp {
                    // vsync_queue_ns: time from submit to display, about one refresh.
                    alvr_report_submit(queuedFrame!.timestamp, vsyncTimeNs)
                    self.lastSubmittedTimestamp = queuedFrame!.timestamp
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
    
    // Poll for NALs and and, when decoded, add them to the frameQueue
        func handleNals() {
            timeLastFrameGot = CACurrentMediaTime()
            
            // Prevent NAL buildup
            if !renderStarted {
                VideoHandler.abandonAllPendingNals()
                return
            }
            
            while renderStarted {
                guard let (timestamp, viewParams, nal) = VideoHandler.pollNal() else {
                    break
                }
                
                objc_sync_enter(frameQueueLock)
                framesSinceLastIDR += 1

                // If we're receiving NALs timestamped from >400ms ago, stop decoding them
                // to prevent a cascade of needless decoding lag
                let ns_diff_from_last_req_ts = lastRequestedTimestamp > timestamp ? lastRequestedTimestamp &- timestamp : 0
                let lagSpiked = (ns_diff_from_last_req_ts > 1000*1000*600 && framesSinceLastIDR > 90*2)
                
                if CACurrentMediaTime() - stutterSampleStart >= 60.0 {
                    print("Stuttter events in the last minute:", stutterEventsCounted)
                    stutterSampleStart = CACurrentMediaTime()
                    
                    if stutterEventsCounted >= 50 {
                        print("AWDL detected!")
//                        if ALVRClientApp.gStore.settings.dontShowAWDLAlertAgain {
//                            print("User doesn't want to see the alert.")
//                        }
//                        else {
//                            DispatchQueue.main.async {
//                                if self.awdlAlertPresented {
//                                    return
//                                }
//                                self.awdlAlertPresented = true
//                                
//                                // Not super kosher but I don't see another way.
//                                // ALVRClientApp.shared.openWindow(id: "AWDLAlert")
//                            }
//                        }
                    }
                    
                    stutterEventsCounted = 0
                }
                if ns_diff_from_last_req_ts > 1000*1000*40 {
                    if (CACurrentMediaTime() - lastStutterTime > 0.25 && CACurrentMediaTime() - lastStutterTime < 10.0) || ns_diff_from_last_req_ts > 1000*1000*100 {
                        stutterEventsCounted += 1
                        //print(ns_diff_from_last_req_ts, CACurrentMediaTime() - lastStutterTime)
                    }
                    lastStutterTime = CACurrentMediaTime()
                }
                // TODO: adjustable framerate
                // TODO: maybe also call this if we fail to decode for too long.
                if lastRequestedTimestamp != 0 && (lagSpiked || framesSinceLastDecode > 90*2) {
                    objc_sync_exit(frameQueueLock)

                    print("Handle spike!", framesSinceLastDecode, framesSinceLastIDR, ns_diff_from_last_req_ts)

                    // We have to request an IDR to resume the video feed
                    VideoHandler.abandonAllPendingNals()
                    alvr_request_idr()
                    framesSinceLastIDR = 0
                    framesSinceLastDecode = 0

                    continue
                }
                objc_sync_exit(frameQueueLock)
                
                let startedDecodeTime = CACurrentMediaTime()

                if let vtDecompressionSession = vtDecompressionSession {
                    VideoHandler.feedVideoIntoDecoder(decompressionSession: vtDecompressionSession, nals: nal, timestamp: timestamp, videoFormat: videoFormat!) { [self] imageBuffer in
                        guard let imageBuffer = imageBuffer else {
                            return
                        }
                        
                        if (CACurrentMediaTime() - startedDecodeTime > Double(50*MSEC_PER_SEC)) {
                            objc_sync_enter(frameQueueLock)

                            print("Handle decode overrun!", CACurrentMediaTime() - startedDecodeTime, framesSinceLastDecode, framesSinceLastIDR, ns_diff_from_last_req_ts)

                            // We have to request an IDR to resume the video feed
                            VideoHandler.abandonAllPendingNals()
                            alvr_request_idr()
                            framesSinceLastIDR = 0
                            framesSinceLastDecode = 0
                            objc_sync_exit(frameQueueLock)

                            return
                        }
                        
                        //print(timestamp, (CACurrentMediaTime() - timeLastFrameDecoded) * 1000.0)
                        timeLastFrameDecoded = CACurrentMediaTime()

                        //let imageBufferPtr = Unmanaged.passUnretained(imageBuffer).toOpaque()
                        //print("finish decode: \(timestamp), \(imageBufferPtr), \(nal_type)")

                        objc_sync_enter(frameQueueLock)
                        framesSinceLastDecode = 0
                        if frameQueueLastTimestamp != timestamp || true
                        {
                            alvr_report_frame_decoded(timestamp)

                            // TODO: For some reason, really low frame rates seem to decode the wrong image for a split second?
                            // But for whatever reason this is fine at high FPS.
                            // From what I've read online, the only way to know if an H264 frame has actually completed is if
                            // the next frame is starting, so keep this around for now just in case.
                            if frameQueueLastImageBuffer != nil {
                                //frameQueue.append(QueuedFrame(imageBuffer: frameQueueLastImageBuffer!, timestamp: frameQueueLastTimestamp))
                                frameQueue.append(QueuedFrame(imageBuffer: imageBuffer, timestamp: timestamp, viewParams: viewParams))
                            }
                            else {
                                frameQueue.append(QueuedFrame(imageBuffer: imageBuffer, timestamp: timestamp, viewParams: viewParams))
                            }
                            if frameQueue.count > 3 {
                                frameQueue.removeFirst()
                            }


                            frameQueueLastTimestamp = timestamp
                            frameQueueLastImageBuffer = imageBuffer
                            timeLastFrameSent = CACurrentMediaTime()
                        }

                        // Pull the very last imageBuffer for a given timestamp
                        if frameQueueLastTimestamp == timestamp {
                            frameQueueLastImageBuffer = imageBuffer
                        }

                        objc_sync_exit(frameQueueLock)
                    }
                } else {
                    alvr_report_frame_decoded(timestamp)
                    alvr_report_compositor_start(timestamp)
                    alvr_report_submit(timestamp, 0)
                }
            }
        }
    
    func createDecoder() {
        // Don't reinstantiate the decoder if it's already created.
        // TODO: Switching from H264 -> HEVC at runtime?
        if vtDecompressionSession != nil {
            handleNals()
            return
        }
        
        while true {
            guard let (_, _, nal) = VideoHandler.pollNal() else {
                fatalError("create decoder: failed to poll nal?!")
                break
            }
            //print(nal.count, timestamp)
            NSLog("%@", nal as NSData)
            let val = (nal[4] & 0x7E) >> 1
            print("NAL type of \(val)")
            if (nal[3] == 0x01 && nal[4] & 0x1f == H264_NAL_TYPE_SPS) || (nal[2] == 0x01 && nal[3] & 0x1f == H264_NAL_TYPE_SPS) {
                // here we go!
                (vtDecompressionSession, videoFormat) = VideoHandler.createVideoDecoder(initialNals: nal, codec: H264_NAL_TYPE_SPS)
                break
            } else if (nal[3] == 0x01 && (nal[4] & 0x7E) >> 1 == HEVC_NAL_TYPE_VPS) || (nal[2] == 0x01 && (nal[3] & 0x7E) >> 1 == HEVC_NAL_TYPE_VPS) {
                // The NAL unit type is 32 (VPS)
                (vtDecompressionSession, videoFormat) = VideoHandler.createVideoDecoder(initialNals: nal, codec: HEVC_NAL_TYPE_VPS)
                break
            }
        }
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
    
    func updateFrame() {
        if !renderStarted {
            renderStarted = true
        }
        
        handleNals()
//        while true {
//            guard let (nal, timestamp) = VideoHandler.pollNal() else {
//                break
//            }
//            
//            framesSinceLastIDR += 1
//            
//            // Don't submit NALs for decoding if we have already decoded a later frame
//            objc_sync_enter(frameQueueLock)
//            if timestamp < frameQueueLastTimestamp {
//                //print("Skip:", timestamp, frameQueueLastTimestamp)
//                //objc_sync_exit(frameQueueLock)
//                //break
//            }
//            
//            // If we're receiving NALs timestamped from >400ms ago, stop decoding them
//            // to prevent a cascade of needless decoding lag
//            let ns_diff_from_last_req_ts = lastRequestedTimestamp > timestamp ? lastRequestedTimestamp &- timestamp : 0
//            let lagSpiked = (ns_diff_from_last_req_ts > 1000*1000*600 && framesSinceLastIDR > 90*2)
//            // TODO: adjustable framerate
//            // TODO: maybe also call this if we fail to decode for too long.
//            if lastRequestedTimestamp != 0 && (lagSpiked || framesSinceLastDecode > 90*2) {
//                objc_sync_exit(frameQueueLock)
//                                    
//                print("Handle spike!", framesSinceLastDecode, framesSinceLastIDR, ns_diff_from_last_req_ts)
//                                    
//                // We have to request an IDR to resume the video feed
//                VideoHandler.abandonAllPendingNals()
//                alvr_request_idr()
//                framesSinceLastIDR = 0
//                framesSinceLastDecode = 0
//                                    
//                continue
//            }
//            objc_sync_exit(frameQueueLock)
//            
//            if let vtDecompressionSession = vtDecompressionSession {
//                VideoHandler.feedVideoIntoDecoder(decompressionSession: vtDecompressionSession, nals: nal, timestamp: timestamp, videoFormat: videoFormat!) { [weak self] imageBuffer in
//                    guard let imageBuffer = imageBuffer else {
//                        return
//                    }
//                    
//                    self?.processFrame(imageBuffer: imageBuffer)
//                    self?.updateFrameStats()
//                }
//            } else {
//                print("WARN: vtDecompressionSession is nil!")
//                // TODO(zhuowei): hax
//                // OR NOT? (kotleni)
//                alvr_report_frame_decoded(timestamp)
//                alvr_report_compositor_start(timestamp)
//                alvr_report_submit(timestamp, 0)
//            }
//        }
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

        // The frame comes back with the eye poses and FOVs it was rendered for (what
        // sendTracking sent for its timestamp). Fall back to our own FOV if they're unset.
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
