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
import AVFoundation
import AudioToolbox
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
    func bindCamera(encoder: MTLRenderCommandEncoder, commandBuffer: MTLCommandBuffer, displayHead: simd_float4x4,
                    allowPassthrough: Bool = true) {
        let s = VRSettings.current
        var c = VRCameraUniforms()
        c.key = SIMD4<Float>(s.keyMode, s.keyTolerance, 0.05, 0)
        var luma: MTLTexture = placeholderTexture
        var chroma: MTLTexture = placeholderTexture
        var depth: MTLTexture = placeholderTexture
        var depthFull: MTLTexture = placeholderTexture
        var personMatte: MTLTexture = placeholderTexture
        var personDepthTex: MTLTexture = placeholderTexture
        if allowPassthrough, s.passthrough > 0.5, let cam = EventHandler.shared.latestCameraFrame(),
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
    var testMode = true                 // the app opens in the sword game (a test-mode scene)
    var saberMode = true                // with testMode: the sword game instead of the test room
    let saberGame = SaberGame()
    private var saberFrame = 0
    private var namedTextures: [String: MTLTexture] = [:]
    private var monitorPipeline: MTLRenderPipelineState?
    private var monitorTexture: MTLTexture?
    private var monitorBusy = false
    private let monitorQueue = DispatchQueue(label: "monitor", qos: .utility)

    /// About 10 times a second, a 512 x 256 copy of both eyes goes to the admin page as a JPEG.
    private func captureMonitor(commandBuffer: MTLCommandBuffer, eyes: MTLTexture) {
        if monitorBusy { return }
        if monitorPipeline == nil {
            let d = MTLRenderPipelineDescriptor()
            let lib = metalDevice.makeDefaultLibrary()
            d.vertexFunction = lib?.makeFunction(name: "mapTexture")
            d.fragmentFunction = lib?.makeFunction(name: "monitorCopy")
            d.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
            monitorPipeline = try? metalDevice.makeRenderPipelineState(descriptor: d)
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: 512, height: 256, mipmapped: false)
            td.usage = [.renderTarget]
            td.storageMode = .shared
            monitorTexture = metalDevice.makeTexture(descriptor: td)
        }
        guard let pipeline = monitorPipeline, let tex = monitorTexture else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = tex
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentTexture(eyes, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 1)
        enc.endEncoding()
        monitorBusy = true
        commandBuffer.addCompletedHandler { [weak self] _ in
            guard let self else { return }
            var bytes = [UInt8](repeating: 0, count: 512 * 256 * 4)
            tex.getBytes(&bytes, bytesPerRow: 512 * 4, from: MTLRegionMake2D(0, 0, 512, 256), mipmapLevel: 0)
            self.monitorQueue.async {
                defer { self.monitorBusy = false }
                let info = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue)
                guard let provider = CGDataProvider(data: Data(bytes) as CFData),
                      let cg = CGImage(width: 512, height: 256, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 512 * 4,
                                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info, provider: provider,
                                       decode: nil, shouldInterpolate: false, intent: .defaultIntent),
                      let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.3) else { return }
                HandReceiver.shared.sendMonitor(jpeg)
            }
        }
    }
    private var propsBuffer: MTLBuffer?
    private var propsVersion = -1
    /// 360 backgrounds by scene: 0 neon grid (none), 1 forest, 2 space, 3 Moon, 4 volcano, 5 study (the forest outside its window).
    static let sceneNames = ["", "scene_forest", "scene_space", "scene_moon", "scene_volcano", "scene_forest", ""]   // 6: tightrope (drawn, no photo)

    /// The 360 background for a scene, loaded from the asset catalog the first time it's used.
    private func panoTexture(_ id: Int) -> MTLTexture {
        guard id > 0, id < Renderer.sceneNames.count else { return placeholderTexture }
        return namedTexture(Renderer.sceneNames[id])
    }

    private func namedTexture(_ name: String) -> MTLTexture {
        if let tex = namedTextures[name] { return tex }
        guard let image = UIImage(named: name)?.cgImage,
              let tex = try? MTKTextureLoader(device: metalDevice).newTexture(cgImage: image, options: [
                .SRGB: false, .generateMipmaps: true, .textureStorageMode: MTLStorageMode.private.rawValue]) else {
            return placeholderTexture
        }
        if name.hasPrefix("scene_") { namedTextures = namedTextures.filter { !$0.key.hasPrefix("scene_") } }   // one 8K background at a time
        namedTextures[name] = tex
        return tex
    }
    private var saberEyesPipelineState: MTLRenderPipelineState?
    private var testEyesPipelineState: MTLRenderPipelineState?
    private var frameRGBPipelineState: MTLRenderPipelineState?
    private var testEyesTexture: MTLTexture?
    private var testDistanceTexture: MTLTexture?   // virtual distance per pixel, for occlusion
    private var sharpEyesTexture: MTLTexture?      // 3072 x 1536: the immersive scenes
    private var sharpDistanceTexture: MTLTexture?
    private var poseHistory: [(time: Double, head: simd_float4x4)] = []

    func drawTestScene(drawable: CAMetalDrawable, renderPassDescriptor: MTLRenderPassDescriptor) {
        if testEyesPipelineState == nil {
            testEyesPipelineState = try! Renderer.buildRenderPipelineWithDevice(device: metalDevice, fragment: "vrTestEyes",
                                                                                 secondColorFormat: .r16Float)
            saberEyesPipelineState = try! Renderer.buildRenderPipelineWithDevice(device: metalDevice, fragment: "vrSaberEyes",
                                                                                  secondColorFormat: .r16Float)
            frameRGBPipelineState = try! Renderer.buildRenderPipelineWithDevice(device: metalDevice, fragment: "vrStreamRGB")
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: globalPixelFormat, width: 2048, height: 1024, mipmapped: false)
            desc.usage = [.renderTarget, .shaderRead]
            desc.storageMode = .private
            testEyesTexture = metalDevice.makeTexture(descriptor: desc)
            desc.pixelFormat = .r16Float
            testDistanceTexture = metalDevice.makeTexture(descriptor: desc)
            let hd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: globalPixelFormat, width: 3072, height: 1536, mipmapped: false)
            hd.usage = [.renderTarget, .shaderRead]
            hd.storageMode = .private
            sharpEyesTexture = metalDevice.makeTexture(descriptor: hd)
            hd.pixelFormat = .r16Float
            sharpDistanceTexture = metalDevice.makeTexture(descriptor: hd)
        }
        // Immersive scenes are cheap to draw, so they get 1.5x the pixels per eye.
        let sharp = saberMode && saberGame.sceneId > 0
        let eyesTex = sharp ? sharpEyesTexture : testEyesTexture
        let distTex = sharp ? sharpDistanceTexture : testDistanceTexture
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
        if saberMode { displayUniforms.misc.y = 0 }   // the sword game is fully virtual: no camera behind it
        var renderUniforms = displayUniforms
        renderUniforms.headToWorld = renderedHead
        var frameUniforms = Renderer.makeFrameUniforms(renderedHead: renderedHead, displayHead: displayHead,
                                                       fovTan: settings.eyeFovTangents())

        // Pass 1: "the PC" renders both eyes at the delayed pose.
        let eyesPass = MTLRenderPassDescriptor()
        eyesPass.colorAttachments[0].texture = eyesTex
        eyesPass.colorAttachments[0].loadAction = .dontCare
        eyesPass.colorAttachments[0].storeAction = .store
        eyesPass.colorAttachments[1].texture = distTex
        eyesPass.colorAttachments[1].loadAction = .dontCare
        eyesPass.colorAttachments[1].storeAction = .store
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: eyesPass) {
            encoder.label = "Test eyes"
            encoder.setRenderPipelineState(saberMode ? saberEyesPipelineState! : testEyesPipelineState!)
            encoder.setFragmentBytes(&renderUniforms, length: MemoryLayout<VRUniforms>.stride, index: 0)
            encoder.setFragmentBytes(&frameUniforms, length: MemoryLayout<VRFrameUniforms>.stride, index: 1)
            if saberMode {
                saberGame.update(head: renderedHead, now: now)
                let scene = saberGame.scene()
                scene.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 2) }
                encoder.setFragmentTexture(saberGame.sceneId > 0 ? panoTexture(saberGame.sceneId) : placeholderTexture, index: 0)
                encoder.setFragmentTexture([2, 3, 5].contains(saberGame.sceneId) ? namedTexture("earth_texture") : placeholderTexture, index: 1)
                let (props, version) = saberGame.props()
                if version != propsVersion || propsBuffer == nil {
                    propsBuffer = props.withUnsafeBytes { metalDevice.makeBuffer(bytes: $0.baseAddress!, length: max($0.count, 64)) }
                    propsVersion = version
                }
                encoder.setFragmentBuffer(propsBuffer, offset: 0, index: 3)
                encoder.setFragmentTexture(Jumpscare.hasAtlas ? namedTexture("jumpscare_atlas")
                                           : Jumpscare.hasCustomImage ? namedTexture("jumpscare_custom") : placeholderTexture, index: 2)
                saberFrame += 1
                if saberFrame % 2 == 0 { HandReceiver.shared.sendSpectator(head: renderedHead, scene: scene) }   // 30-60 Hz live view
            }
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 1)
            encoder.endEncoding()
        }
        if saberMode && saberFrame % 4 == 0, let eyes = eyesTex {            // monitor video, as fast as the encoder keeps up
            captureMonitor(commandBuffer: commandBuffer, eyes: eyes)
        }
        // Pass 2: the phone shows it through the lenses, reprojected to the current head.
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            encoder.label = "Lens pass (test)"
            encoder.setRenderPipelineState(frameRGBPipelineState!)
            encoder.setFragmentBytes(&displayUniforms, length: MemoryLayout<VRUniforms>.stride, index: 0)
            encoder.setFragmentBytes(&frameUniforms, length: MemoryLayout<VRFrameUniforms>.stride, index: 1)
            encoder.setFragmentTexture(eyesTex, index: 0)
            encoder.setFragmentTexture(distTex, index: 1)
            bindCamera(encoder: encoder, commandBuffer: commandBuffer, displayHead: displayHead, allowPassthrough: !saberMode)
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


// MARK: - Sword game (no SteamVR)
// Emergency mode: the phone runs the sword game itself and draws it with vrSaberEyes
// (Shaders.metal) through the same lens pass as test mode, so SteamVR and the video
// stream aren't involved. The hands come from the laptop bridge over UDP through the
// USB hotspot: `python -m myphonevision_bridge --no-hmd --phone 172.20.10.1`.

/// Receives hand poses from the bridge: b"MPVH", hand, 3 pad bytes, then position
/// x y z (m) and rotation w x y z as little-endian floats, in SteamVR axes.
final class HandReceiver {
    static let shared = HandReceiver()
    static let port: UInt16 = 39601
    private let lock = NSLock()
    private var poses: [simd_float4x4] = [matrix_identity_float4x4, matrix_identity_float4x4]
    private var stamps: [Double] = [0, 0]
    private var buttonBits: [UInt8] = [0, 0]
    private var commandBytes: (UInt8, UInt8) = (0, 0)   // from the admin page: command, sequence
    private var started = false
    private var fd: Int32 = -1
    private var sender = sockaddr_in6()   // the bridge: where the live view goes back to
    private var haveSender = false

    func start() {
        lock.lock(); defer { lock.unlock() }
        if started { return }
        started = true
        let thread = Thread { [weak self] in self?.run() }
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    private func run() {
        // IPv6 socket that also takes IPv4: some carriers' hotspots are IPv6-only.
        let fd = socket(AF_INET6, SOCK_DGRAM, 0)
        guard fd >= 0 else { print("HandReceiver: no socket"); return }
        var one: Int32 = 1, off: Int32 = 0
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &off, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in6()
        addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        addr.sin6_family = sa_family_t(AF_INET6)
        addr.sin6_port = HandReceiver.port.bigEndian
        addr.sin6_addr = in6addr_any
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) }
        }
        guard bound == 0 else { print("HandReceiver: bind failed"); close(fd); return }
        lock.lock(); self.fd = fd; lock.unlock()
        var buf = [UInt8](repeating: 0, count: 128)
        while true {
            var from = sockaddr_in6()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in6>.size)
            let n = buf.withUnsafeMutableBytes { b in
                withUnsafeMutablePointer(to: &from) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, b.baseAddress, b.count, 0, $0, &fromLen) }
                }
            }
            guard n >= 36, buf[0] == 0x4D, buf[1] == 0x50, buf[2] == 0x56, buf[3] == 0x48 else { continue }
            let hand = Int(buf[4])
            if hand == 255 {   // keepalive from the bridge with no controllers: admin commands and the video's return address only
                lock.lock(); commandBytes = (buf[6], buf[7]); sender = from; haveSender = true; lock.unlock()
                continue
            }
            guard hand == 0 || hand == 1 else { continue }
            let f: [Float] = buf.withUnsafeBytes { raw in (0..<7).map { raw.loadUnaligned(fromByteOffset: 8 + 4 * $0, as: Float.self) } }
            var m = simd_float4x4(simd_normalize(simd_quatf(ix: f[4], iy: f[5], iz: f[6], r: f[3])))
            m.columns.3 = SIMD4<Float>(f[0], f[1], f[2], 1)
            lock.lock()
            poses[hand] = m
            buttonBits[hand] = buf[5]
            commandBytes = (buf[6], buf[7])
            sender = from
            haveSender = true
            stamps[hand] = CACurrentMediaTime()
            lock.unlock()
        }
    }

    /// Sends the game state back to the bridge (UDP 39602) for the tuner page's live view:
    /// b"MPVS", head position, forward and up, then the scene floats (boxes in use only).
    func sendSpectator(head: simd_float4x4, scene: [SIMD4<Float>]) {
        lock.lock()
        guard haveSender, fd >= 0 else { lock.unlock(); return }
        var to = sender
        let sock = fd
        lock.unlock()
        to.sin6_port = UInt16(39602).bigEndian
        let boxes = min(Int(scene[6].x), 10)   // stay under one network packet (no fragments to lose)
        let used = min(scene.count, 19 + boxes * 5)
        var floats: [Float] = [head.columns.3.x, head.columns.3.y, head.columns.3.z,
                               -head.columns.2.x, -head.columns.2.y, -head.columns.2.z,
                               head.columns.1.x, head.columns.1.y, head.columns.1.z]
        for v in scene[0..<used] { floats += [v.x, v.y, v.z, v.w] }
        floats[9 + 6 * 4] = Float(boxes)
        var bytes: [UInt8] = [0x4D, 0x50, 0x56, 0x53]
        floats.withUnsafeBytes { bytes += $0 }
        _ = bytes.withUnsafeBytes { b in
            withUnsafePointer(to: &to) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(sock, b.baseAddress, b.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
        }
    }

    /// The admin page's latest command (1 recenter play area, 2 reset score) and its sequence number.
    func command() -> (id: UInt8, seq: UInt8) {
        lock.lock(); defer { lock.unlock() }
        return commandBytes
    }

    /// Sends one monitor JPEG to the bridge (UDP 39603) in pieces that each fit one network packet:
    /// b"MPVJ", frame number, piece index, piece count (UInt16 each, little-endian), 2 pad bytes, data.
    private var monitorFrame: UInt16 = 0
    func sendMonitor(_ jpeg: Data) {
        lock.lock()
        guard haveSender, fd >= 0 else { lock.unlock(); return }
        var to = sender
        let sock = fd
        monitorFrame &+= 1
        let frame = monitorFrame
        lock.unlock()
        to.sin6_port = UInt16(39603).bigEndian
        let chunk = 1180
        let count = (jpeg.count + chunk - 1) / chunk
        guard count > 0, count < 200 else { return }
        for i in 0..<count {
            var pkt: [UInt8] = [0x4D, 0x50, 0x56, 0x4A]
            for v in [frame, UInt16(i), UInt16(count), 0] { pkt += [UInt8(v & 0xFF), UInt8(v >> 8)] }
            pkt += jpeg[jpeg.startIndex + i * chunk ..< jpeg.startIndex + min(jpeg.count, (i + 1) * chunk)]
            _ = pkt.withUnsafeBytes { b in
                withUnsafePointer(to: &to) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(sock, b.baseAddress, b.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
                    }
                }
            }
        }
    }

    /// A hand's buttons: bit 0 A, bit 1 stick click, bit 2 realign (from the bridge's tuner page).
    func buttons(_ hand: Int) -> UInt8 {
        lock.lock(); defer { lock.unlock() }
        return buttonBits[hand]
    }

    /// A hand's latest pose, or nil if nothing came in the last half second.
    func pose(_ hand: Int) -> simd_float4x4? {
        lock.lock(); defer { lock.unlock() }
        return CACurrentMediaTime() - stamps[hand] < 0.5 ? poses[hand] : nil
    }
}

/// The sword game: cubes float around you; a fast swing slices one, a slow one pushes it.
final class SaberGame {
    struct Cube {
        var pos: SIMD3<Float>, home: SIMD3<Float>, vel: SIMD3<Float>
        var rot: simd_quatf, spinAxis: SIMD3<Float>, spin: Float
        var half: Float, color: SIMD3<Float>, age: Float, phase: Float, cooldown: Float
    }
    struct Piece {
        var pos: SIMD3<Float>, vel: SIMD3<Float>, rot: simd_quatf, spinAxis: SIMD3<Float>, spin: Float
        var half: SIMD3<Float>, color: SIMD3<Float>, life: Float, cutAxis: Int, cutSide: Float
    }
    struct Blade {
        var a = SIMD3<Float>(repeating: 0), b = SIMD3<Float>(repeating: 0)
        var prevA = SIMD3<Float>(repeating: 0), prevB = SIMD3<Float>(repeating: 0)
        var hilt = SIMD3<Float>(repeating: 0), dir = SIMD3<Float>(0, 0, -1)
        var valid = false, length: Float = 0
    }
    static let colors: [SIMD3<Float>] = [SIMD3(0.15, 0.55, 1.0), SIMD3(1.0, 0.25, 0.08)]   // left, right
    static let maxBoxes = 24
    let lock = NSLock()
    var cubes: [Cube] = [], pieces: [Piece] = []
    var flashes: [(pos: SIMD3<Float>, color: SIMD3<Float>, age: Float)] = []
    var blades = [Blade(), Blade()]
    var score = 0, combo = 0
    var t: Float = 0, lastSlice: Float = -10, spawnTimer: Float = 0
    var anchorPos = SIMD3<Float>(0, 1.6, 0), anchorFwd = SIMD3<Float>(0, 0, -1), anchored = false
    var headPos = SIMD3<Float>(0, 1.6, 0), headFwd = SIMD3<Float>(0, 0, -1)
    var handYaw: [Float] = [0, 0]          // turns each controller so it points where you faced at the last tap
    var alignPending = [true, true]
    var handLift: [Float] = [0, 0]          // height correction per hand, set when the blades realign
    var measureLift = [true, true]
    var aWasDown = [false, false], realignWasOn = false
    var lastCommandSeq: UInt8? = nil   // first one seen is only remembered, not run
    var sceneId = UserDefaults.standard.integer(forKey: "vrScene") {   // 0 sword game (neon grid); 1 forest, 2 space, 3 Moon, 4 volcano, 6 tightrope
        didSet { UserDefaults.standard.set(sceneId, forKey: "vrScene") }
    }
    var immersive: Bool { sceneId > 0 }   // the scenes are for looking around: no blades, cubes or score
    var mode = 0                       // 0 sword game, 1 explore (no cubes or score)
    var jumpscareAt: Float? = nil      // game time the admin page's Jumpscare started
    private var propsCache: [SIMD4<Float>] = [], propsKey = "", propsVersion = 0

    /// The current scene's 3D props (rebuilt when the scene or the play area changes) and a version number.
    func props() -> ([SIMD4<Float>], Int) {
        lock.lock(); defer { lock.unlock() }
        let moving = sceneId == 2 ? " \(Int(t * 60))" : ""   // space: the Moon and satellite orbit
        let key = "\(sceneId) \(anchorPos.x) \(anchorPos.z) \(anchorFwd.x) \(anchorFwd.z)" + moving
        if key != propsKey {
            propsCache = SceneProps.build(sceneId, origin: anchorPos, forward: anchorFwd, time: t)
            propsKey = key
            propsVersion += 1
        }
        return (propsCache, propsVersion)
    }
    var aClicks: [[Float]] = [[], []]   // recent A presses: three within 1.2 s realign that blade
    var lastTime: Double = 0

    /// The settings screen's scene picker.
    func setScene(_ id: Int) {
        lock.lock(); defer { lock.unlock() }
        sceneId = id
        anchored = false
    }

    /// Put the play area in front of the current head again (on tap to recenter).
    func recenter() {
        lock.lock(); defer { lock.unlock() }
        anchored = false
        alignPending = [true, true]
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        cubes.removeAll(); pieces.removeAll(); flashes.removeAll()
        score = 0; combo = 0; anchored = false; lastTime = 0
        alignPending = [true, true]
        blades = [Blade(), Blade()]
    }

    private static func rnd(_ a: Float, _ b: Float) -> Float { Float.random(in: a...b) }
    private static func randomAxis() -> SIMD3<Float> {
        simd_normalize(SIMD3(rnd(-1, 1), rnd(-1, 1), rnd(-1, 1)) + SIMD3(0.001, 0.002, 0.003))
    }

    func update(head: simd_float4x4, now: Double) {
        lock.lock(); defer { lock.unlock() }
        let dt = lastTime == 0 ? Float(1.0 / 60) : Float(min(0.05, max(0.001, now - lastTime)))
        lastTime = now
        t += dt
        let hp = SIMD3<Float>(head.columns.3.x, head.columns.3.y, head.columns.3.z)
        var fwd = -SIMD3<Float>(head.columns.2.x, 0, head.columns.2.z)
        fwd = simd_length(fwd) > 1e-3 ? simd_normalize(fwd) : SIMD3(0, 0, -1)
        headPos = hp; headFwd = fwd
        let cmd = HandReceiver.shared.command()
        if let last = lastCommandSeq, cmd.seq != last {
            if cmd.id == 1 { anchored = false }            // recenter play area: cubes and scoreboard in front of the player
            if cmd.id == 2 { score = 0; combo = 0 }        // reset score
            if (10...16).contains(cmd.id) {                                // switch scene
                sceneId = Int(cmd.id) - 10
                anchored = false                                           // lay it out in front of the player
            }
            if cmd.id == 30 { jumpscareAt = t; Jumpscare.play() }         // jumpscare
            if cmd.id == 31 { OrientationLock.lockUprightNow() }           // the way the phone sits now is upright
            if cmd.id == 32 { OrientationLock.flip() }                     // turn the picture 180°
            if cmd.id == 33 { OrientationLock.unlock() }                   // automatic rotation again
            if (20...21).contains(cmd.id) {                                // switch mode
                mode = Int(cmd.id) - 20
                if mode == 0 { anchored = false } else { cubes.removeAll() }
            }
        }
        lastCommandSeq = cmd.seq
        if !anchored {   // start (or recenter): the cubes and the scoreboard go in front of where you face
            anchorPos = hp; anchorFwd = fwd; anchored = true
            cubes.removeAll(); pieces.removeAll()
            if mode == 0 && !immersive { for _ in 0..<8 { spawn() } }
            spawnTimer = 0.35
        }

        for h in 0..<2 {
            guard var m = HandReceiver.shared.pose(h) else { blades[h].valid = false; blades[h].length = 0; continue }
            let bits = HandReceiver.shared.buttons(h)
            let aDown = bits & 1 != 0
            if aDown && !aWasDown[h] {   // triple-click A: this blade lines up with where you're looking
                aClicks[h] = aClicks[h].filter { t - $0 < 1.2 } + [t]
                if aClicks[h].count >= 3 { alignPending[h] = true; aClicks[h].removeAll() }
            }
            aWasDown[h] = aDown
            if h == 0 {   // the tuner page's Realign button: both blades
                let on = bits & 4 != 0
                if on && !realignWasOn { alignPending = [true, true] }
                realignWasOn = on
            }
            if alignPending[h] {   // at the start, on a tap, triple-click or Realign: where the controller points becomes where you look
                let f0 = -SIMD3<Float>(m.columns.2.x, 0, m.columns.2.z)
                if simd_length(f0) > 0.3 {
                    handYaw[h] = atan2(f0.x, -f0.z) - atan2(fwd.x, -fwd.z)   // controller's heading -> where the head faces
                    alignPending[h] = false
                    measureLift[h] = true
                    if blades[h].valid {
                        flashes.append((blades[h].a, SaberGame.colors[h], 0))
                        if flashes.count > 4 { flashes.removeFirst() }
                    }
                }
            }
            m = simd_float4x4(simd_quatf(angle: handYaw[h], axis: SIMD3<Float>(0, 1, 0))) * m   // about the head (x = z = 0)
            m.columns.3.x += hp.x   // the bridge places hands for a head at x = z = 0
            m.columns.3.z += hp.z
            if measureLift[h] {      // on realign: this hand goes to chest height, 42 cm below the eyes, both hands level
                handLift[h] = (hp.y - 0.42) - m.columns.3.y
                measureLift[h] = false
            }
            m.columns.3.y += handLift[h]
            var b = blades[h]
            let d = simd_normalize(-SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z))
            let origin = SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
            b.length = min(1.0, b.length + dt / 0.25)
            let a = origin + d * 0.15
            if b.valid { b.prevA = b.a; b.prevB = b.b } else { b.prevA = a; b.prevB = a + d * b.length }
            b.a = a; b.b = a + d * b.length; b.hilt = origin - d * 0.12; b.dir = d; b.valid = true
            blades[h] = b
        }
        collide(dt)

        // Floating cubes: spring toward home with a gentle bob, spin, keep apart.
        for i in cubes.indices {
            var c = cubes[i]
            c.age += dt; c.cooldown -= dt
            c.rot = simd_normalize(simd_quatf(angle: c.spin * dt, axis: c.spinAxis) * c.rot)
            let home = c.home + SIMD3(0, 0.03 * sin(c.age * 1.3 + c.phase), 0)
            c.vel += (4.0 * (home - c.pos) - 2.5 * c.vel) * dt
            c.pos += c.vel * dt
            cubes[i] = c
        }
        for i in cubes.indices {
            for j in cubes.indices where j > i {
                let d = cubes[i].pos - cubes[j].pos
                let L = simd_length(d)
                let gap = (cubes[i].half + cubes[j].half) * 1.24 + 0.04
                if L > 1e-5 && L < gap {
                    let push = d / L * (gap - L) * 6 * dt
                    cubes[i].vel += push * 10; cubes[j].vel -= push * 10
                    cubes[i].home += push; cubes[j].home -= push
                }
            }
        }
        cubes.removeAll { $0.pos.y < 0.1 || simd_length($0.pos - hp) > 8 }
        spawnTimer -= dt
        if immersive { cubes.removeAll(); pieces.removeAll() }
        if mode == 0 && !immersive && cubes.count < 8 && spawnTimer <= 0 { spawn(); spawnTimer = 0.35 }

        for i in pieces.indices {
            var p = pieces[i]
            p.vel.y -= 9.8 * dt
            p.pos += p.vel * dt
            p.rot = simd_normalize(simd_quatf(angle: p.spin * dt, axis: p.spinAxis) * p.rot)
            let R = simd_matrix3x3(p.rot)
            let low = abs(R.columns.0.y) * p.half.x + abs(R.columns.1.y) * p.half.y + abs(R.columns.2.y) * p.half.z
            if p.pos.y < low { p.pos.y = low; p.vel *= SIMD3(0.6, -0.3, 0.6); p.spin *= 0.7 }
            p.life -= dt
            pieces[i] = p
        }
        pieces.removeAll { $0.life <= 0 }
        for i in flashes.indices { flashes[i].age += dt }
        flashes.removeAll { $0.age > 0.3 }
    }

    private func spawn() {
        var home = headPos
        for _ in 0..<12 {   // in front of where you're facing now
            let ang = SaberGame.rnd(-0.9, 0.9)
            let dir = simd_quatf(angle: ang, axis: SIMD3(0, 1, 0)).act(headFwd)
            home = headPos + dir * SaberGame.rnd(0.75, 1.25)
            home.y = SaberGame.rnd(0.95, 1.7)
            if cubes.allSatisfy({ simd_length($0.home - home) > 0.45 }) { break }
        }
        cubes.append(Cube(pos: home, home: home, vel: .zero,
                          rot: simd_quatf(angle: SaberGame.rnd(0, 6.28), axis: SaberGame.randomAxis()),
                          spinAxis: SaberGame.randomAxis(), spin: SaberGame.rnd(0.3, 1.2),
                          half: SaberGame.rnd(0.09, 0.12), color: SaberGame.colors[Int.random(in: 0...1)],
                          age: 0, phase: SaberGame.rnd(0, 6.28), cooldown: 0))
    }

    private func collide(_ dt: Float) {
        for h in 0..<2 {
            let b = blades[h]
            guard b.valid, b.length > 0.2 else { continue }
            var i = 0
            while i < cubes.count {
                let c = cubes[i]
                var sliced = false
                if c.cooldown <= 0 {
                    for u in [Float(0.25), 0.5, 0.75, 1.0] {
                        let A = b.prevA + (b.a - b.prevA) * u, B = b.prevB + (b.b - b.prevB) * u
                        let AB = B - A
                        let s = max(0, min(1, simd_dot(c.pos - A, AB) / max(simd_dot(AB, AB), 1e-6)))
                        let hit = A + AB * s
                        if simd_length(hit - c.pos) < c.half * 1.24 + 0.02 {
                            let nowP: SIMD3<Float> = b.a + (b.b - b.a) * s
                            let prevP: SIMD3<Float> = b.prevA + (b.prevB - b.prevA) * s
                            let v: SIMD3<Float> = (nowP - prevP) / max(dt, Float(1e-3))
                            if simd_length(v) > 1.5 {
                                slice(i, blade: b, velocity: v)
                                sliced = true
                            } else {
                                var away = c.pos - hit
                                away = simd_length(away) > 1e-5 ? simd_normalize(away) : SIMD3(0, 1, 0)
                                let kick: Float = simd_length(v) * 0.8 + 0.4
                                let dv: SIMD3<Float> = away * kick + v * Float(0.4)
                                cubes[i].vel += dv
                                cubes[i].cooldown = 0.15
                            }
                            break
                        }
                    }
                }
                if !sliced { i += 1 }
            }
        }
    }

    private func slice(_ index: Int, blade b: Blade, velocity v: SIMD3<Float>) {
        let c = cubes.remove(at: index)
        var n = simd_cross(b.dir, v)
        n = simd_length(n) > 1e-6 ? simd_normalize(n) : SIMD3(1, 0, 0)
        let R = simd_matrix3x3(c.rot)
        let axes = [R.columns.0, R.columns.1, R.columns.2]
        var k = 0
        for j in 1..<3 where abs(simd_dot(axes[j], n)) > abs(simd_dot(axes[k], n)) { k = j }
        var half = SIMD3<Float>(repeating: c.half)
        half[k] /= 2
        for sgn: Float in [1, -1] {
            let axis = axes[k] * sgn
            let vel = c.vel + v * 0.25 + axis * SaberGame.rnd(1.0, 1.8) + SaberGame.randomAxis() * 0.2
            pieces.append(Piece(pos: c.pos + axis * c.half / 2, vel: vel, rot: c.rot, spinAxis: SaberGame.randomAxis(),
                                spin: SaberGame.rnd(4, 10), half: half, color: c.color, life: 2.0, cutAxis: k, cutSide: -sgn))
        }
        combo = t - lastSlice < 2 ? combo + 1 : 1
        lastSlice = t
        score += combo
        flashes.append((c.pos, simd_clamp(c.color * 0.6 + 0.4, SIMD3(repeating: 0), SIMD3(repeating: 1)), 0))
        if flashes.count > 4 { flashes.removeFirst() }
    }

    /// The scene for vrSaberEyes (layout at the top of its section in Shaders.metal).
    func scene() -> [SIMD4<Float>] {
        lock.lock(); defer { lock.unlock() }
        var S = [SIMD4<Float>](repeating: .zero, count: 19 + SaberGame.maxBoxes * 5)
        for h in 0..<2 {
            let b = blades[h]
            S[h] = SIMD4(b.a, b.valid && !immersive ? 1 : 0)   // no blades in the immersive scenes
            S[2 + h] = SIMD4(b.b, 0)
            S[4 + h] = SIMD4(SaberGame.colors[h], 0)
            S[15 + h] = SIMD4(b.hilt, h == 0 ? atan2(anchorFwd.x, -anchorFwd.z) : 0)
        }
        for (i, f) in flashes.suffix(4).enumerated() {
            let a = f.age / 0.3
            S[7 + i] = SIMD4(f.pos, 0.04 + 0.16 * a)
            S[11 + i] = SIMD4(f.color, 0.8 * (1 - a) * (1 - a))
        }
        var board = anchorPos + anchorFwd * 3.6
        board.y = 2.75
        S[17] = SIMD4(board, immersive ? 1 : Float(mode))
        S[18] = SIMD4(simd_normalize(simd_cross(anchorFwd, SIMD3(0, 1, 0))), Float(sceneId))
        var n = 0
        func box(_ pos: SIMD3<Float>, _ rot: simd_quatf, _ half: SIMD3<Float>, _ color: SIMD3<Float>, _ code: Float) {
            guard n < SaberGame.maxBoxes else { return }
            let R = simd_matrix3x3(rot)
            let o = 19 + n * 5
            S[o] = SIMD4(pos, code)
            S[o + 1] = SIMD4(R.columns.0 * max(half.x, 1e-4), 0)
            S[o + 2] = SIMD4(R.columns.1 * max(half.y, 1e-4), 0)
            S[o + 3] = SIMD4(R.columns.2 * max(half.z, 1e-4), 0)
            S[o + 4] = SIMD4(color, 0)
            n += 1
        }
        for c in cubes {
            let grow = min(1, c.age / 0.3)
            box(c.pos, c.rot, SIMD3(repeating: (1 - pow(1 - grow, 3)) * c.half), c.color, 0)
        }
        for p in pieces {
            let heat = max(0, min(1, (p.life - 1.2) / 0.8))
            box(p.pos, p.rot, p.half * min(1, p.life / 0.4), p.color, p.cutSide * (Float(p.cutAxis) + 1 + 0.9 * heat))
        }
        S[6] = SIMD4(Float(n), t, Float(score), Float(combo))
        if let js = jumpscareAt, t - js < 1.6 { S[16].w = t - js } else { S[16].w = -1; jumpscareAt = nil }
        S[2].w = Jumpscare.hasCustomImage ? 1 : 0
        S[3].w = Jumpscare.hasAtlas ? 1 : 0
        return S
    }
}

/// Static 3D props for each scene, laid out in the play area's frame (x right, y up, -z
/// ahead of where the player faced at the last recenter), packed for vrSaberEyes' buffer 3.
/// These are real 3D objects (unlike the 360 backgrounds), so you can walk up to them.
struct SceneProps {
    var boxes: [SIMD4<Float>] = [], spheres: [SIMD4<Float>] = [], caps: [SIMD4<Float>] = []
    var ambient: Float = 0.45, groundMat: Float = 0, groundRadius: Float = 25
    var sun = SIMD3<Float>(0, 0, 0)   // toward the light, in the play area's frame; zero = the default overhead sun
    var yaw: Float = 0, origin = SIMD3<Float>(0, 0, 0)

    private var turn: simd_quatf { simd_quatf(angle: -yaw, axis: SIMD3<Float>(0, 1, 0)) }
    private func w(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let r = turn.act(SIMD3<Float>(p.x, 0, p.z))
        return SIMD3<Float>(origin.x + r.x, p.y, origin.z + r.z)
    }
    mutating func box(_ c: SIMD3<Float>, _ size: SIMD3<Float>, _ color: SIMD3<Float>, mat: Float = 0, glow: Float = 0, spin: Float = 0) {
        let q = simd_quatf(angle: spin, axis: SIMD3<Float>(0, 1, 0))
        let ax = turn.act(q.act(SIMD3<Float>(size.x / 2, 0, 0)))
        let az = turn.act(q.act(SIMD3<Float>(0, 0, size.z / 2)))
        boxes += [SIMD4(w(c), mat), SIMD4(ax, 0), SIMD4(SIMD3<Float>(0, size.y / 2, 0), 0), SIMD4(az, 0), SIMD4(color, glow)]
    }
    mutating func sphere(_ c: SIMD3<Float>, _ r: Float, _ color: SIMD3<Float>, mat: Float = 0) {
        spheres += [SIMD4(w(c), r), SIMD4(color, mat)]
    }
    mutating func capsule(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ r: Float, _ color: SIMD3<Float>, mat: Float = 0) {
        caps += [SIMD4(w(a), r), SIMD4(w(b), 0), SIMD4(color, mat)]
    }
    func packed() -> [SIMD4<Float>] {
        [SIMD4(Float(boxes.count / 5), Float(spheres.count / 2), Float(caps.count / 3), ambient),
         SIMD4(0, groundMat, groundRadius, 0), SIMD4(simd_length(sun) > 0 ? turn.act(sun) : sun, 0)] + boxes + spheres + caps
    }

    static func build(_ scene: Int, origin o: SIMD3<Float>, forward f: SIMD3<Float>, time: Float = 0) -> [SIMD4<Float>] {
        var s = SceneProps()
        s.origin = SIMD3<Float>(o.x, 0, o.z)
        s.yaw = atan2(f.x, -f.z)
        typealias V = SIMD3<Float>
        switch scene {   // the existing scenes are backgrounds only; ready-made 3D rooms will go here
        default:
            break
        }
        return s.packed()
    }
}


/// The jumpscare's sound (an original synthesized screech, asset "jumpscare_sound") and buzz.
/// Drop your own picture into the asset catalog as "jumpscare_custom" to use it instead of the robot face.
enum Jumpscare {
    static let hasCustomImage = UIImage(named: "jumpscare_custom") != nil
    static let hasAtlas = UIImage(named: "jumpscare_atlas") != nil   // pre-rendered stereo creature (wins over the others)
    private static var player: AVAudioPlayer?

    static func play() {
        DispatchQueue.main.async {
            try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
            if let data = NSDataAsset(name: "jumpscare_sound")?.data, let p = try? AVAudioPlayer(data: data) {
                p.volume = 1.0
                p.play()
                player = p
            }
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }
}
