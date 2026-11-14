//
//  LobbyView.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 26.02.2024.
//

import SwiftUI

/// Lens and screen geometry for the lens pass, saved on the phone.
/// Defaults come from phone/ios/README.md; tune k1 by eye in test mode.
/// Lenses: two Carson TriView TV-26, all 3 lenses stacked per eye, in the
/// headset's sliding focus tubes (headset/headset.scad on branch lens-tubes).
struct VRSettings {
    var k1: Float = 0.24
    var k2: Float = 0.30
    var ipdMm: Float = 63
    var screenToLensMm: Float = 30.5   // stack's middle to the screen, tubes at nominal: ~20 behind the back glass
                                       // + half the 21.1 mm stack (= headset.scad lens_f 33 - focus_back_off 2.5)
    var lensYOffsetMm: Float = 0       // lens centers above (+) or below (-) the screen center
    var fovLimitDeg: Float = 45        // widest angle seen through a lens, per side: the 25.75 mm glass from ~13 mm
                                       // away. Caps the FOV ALVR renders so pixels aren't spent outside the lens
    var eyeHeightM: Float = 1.65       // head height above the floor after a recenter
    var latencyMs: Float = 0           // test mode only: render the room this late, like the stream
    var reprojection: Float = 1        // 1 on, 0 off
    var highRefresh: Float = 1         // 1: 120 Hz display, 0: 60 Hz (cooler)
    var passthrough: Float = 0         // 1: rear camera behind the frame (AR mode)
    var keyMode: Float = 1             // stream pixels that become see-through: 0 none, 1 near-black, 2 magenta
    var keyTolerance: Float = 0.04     // how close to the key color counts as key (linear RGB)
    var lidarDepth: Float = 1          // passthrough depth: 0 fixed 1.5 m, 1 LiDAR scene average (steady), 2 LiDAR smoothed grid (stereo)
    var occlusion: Float = 1           // real things in front hide virtual content: 0 off, 1 people & hands (sharp), 2 LiDAR (everything, fuzzy)
    var handDistanceM: Float = 0.7     // stream only (no virtual depth): real things closer than this cut through

    var displayHz: Int { highRefresh > 0.5 ? 120 : 60 }

    static let screenWidthMm: Float = 144.8   // iPhone 16 Pro: 2622 x 1206 px at 460 ppi
    static let screenHeightMm: Float = 66.6
    static var current = VRSettings.load()

    private static let keys = ["k1", "k2", "ipdMm", "screenToLensMm", "lensYOffsetMm", "fovLimitDeg", "eyeHeightM", "latencyMs", "reprojection", "highRefresh",
                               "passthrough", "keyMode", "keyTolerance", "lidarDepth", "occlusion", "handDistanceM"]
    private static let paths: [WritableKeyPath<VRSettings, Float>] = [\.k1, \.k2, \.ipdMm, \.screenToLensMm, \.lensYOffsetMm, \.fovLimitDeg, \.eyeHeightM, \.latencyMs, \.reprojection, \.highRefresh,
                                                                      \.passthrough, \.keyMode, \.keyTolerance, \.lidarDepth, \.occlusion, \.handDistanceM]

    /// Bump when the lens defaults change for new lenses: phones that saved the old
    /// lens settings start from the new defaults once (the other settings are kept).
    private static let lensDefaultsVersion = 2   // 1: 45 mm placeholder lens; 2: Carson TriView 3-stack
    private static let lensKeys: Set<String> = ["k1", "k2", "screenToLensMm", "fovLimitDeg"]

    static func load() -> VRSettings {
        var s = VRSettings()
        let oldLenses = UserDefaults.standard.integer(forKey: "vr.lensDefaultsVersion") < lensDefaultsVersion
        for (key, path) in zip(keys, paths) {
            if oldLenses && lensKeys.contains(key) { continue }
            if let v = UserDefaults.standard.object(forKey: "vr." + key) as? Float { s[keyPath: path] = v }
        }
        return s
    }

    func save() {
        for (key, path) in zip(VRSettings.keys, VRSettings.paths) {
            UserDefaults.standard.set(self[keyPath: path], forKey: "vr." + key)
        }
        UserDefaults.standard.set(VRSettings.lensDefaultsVersion, forKey: "vr.lensDefaultsVersion")
        VRSettings.current = self
    }

    /// Per eye (left, right): tangents of the left, right, up and down edges of what
    /// the eye sees through its lens, with the same lens model as the shader (left
    /// and down negative), no wider than fovLimitDeg. ALVR renders each eye with this FOV.
    func eyeFovTangents() -> [SIMD4<Float>] {
        let limit = min(2.5, tan(fovLimitDeg * .pi / 180))
        func seen(_ d: Float) -> Float {
            let r2 = d * d
            return max(-limit, min(limit, d * (1 + k1 * r2 + k2 * r2 * r2)))
        }
        let halfW = VRSettings.screenWidthMm / 2, halfH = VRSettings.screenHeightMm / 2
        let up = seen((halfH - lensYOffsetMm) / screenToLensMm)
        let down = seen((-halfH - lensYOffsetMm) / screenToLensMm)
        let outer = seen((halfW - ipdMm / 2) / screenToLensMm)
        let inner = seen((ipdMm / 2) / screenToLensMm)
        return [SIMD4(-outer, inner, up, down), SIMD4(-inner, outer, up, down)]
    }
}

struct SettingSlider: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let step: Float
    let format: String

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value)).monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

class LobbyViewModel: ObservableObject {
    @Published var version: String = ""
    @Published var hostName: String = ""
    @Published var ipAddr: String = ""
    
    @Published var isDontTrackOrientation: Bool = true
    @Published var isDontTrackPosition: Bool = true
    
    func loadSettings() {
        isDontTrackOrientation = UserDefaults.standard.bool(forKey: "isDontTrackOrientation")
        isDontTrackPosition = UserDefaults.standard.bool(forKey: "isDontTrackPosition")
    }
    
    func saveSettings() {
        UserDefaults.standard.setValue(isDontTrackOrientation, forKey: "isDontTrackOrientation")
        UserDefaults.standard.setValue(isDontTrackPosition, forKey: "isDontTrackPosition")
    }
}

struct ListItem: View {
    let title: String
    let content: String
    
    var body: some View {
        HStack {
            Text(title)
                //.bold()
            Spacer()
            Text(content)
        }
    }
}

struct LobbyView: View {
    @State var isPresentedLobby: Binding<Bool>
    
    @ObservedObject private var viewModel = LobbyViewModel()
    @ObservedObject private var eventHandler = EventHandler.shared
    @State private var vr = VRSettings.current

    var body: some View {
        List {
            Section {
                Button("Start") {
                    // Prevent locking screen
                    UIApplication.shared.isIdleTimerDisabled = true

                    isPresentedLobby.wrappedValue = false
                    isPresentedLobby.update()

                    viewModel.saveSettings()
                    vr.save()
                    Renderer.shared?.testMode = false
                    EventHandler.shared.setWorldTrackingParams(isTrackOrientation: !viewModel.isDontTrackOrientation, isTrackPosition: !viewModel.isDontTrackPosition)
                    EventHandler.shared.start()
                }

                Text("Connects to ALVR v20.8.0 on the laptop. Put the headset on facing forward; tap to recenter, hold 1 s to come back here.")
                    .fontWeight(.light)

                Button("Test mode (no server)") {
                    UIApplication.shared.isIdleTimerDisabled = true
                    vr.save()
                    Renderer.shared?.testMode = true
                    EventHandler.shared.setWorldTrackingParams(isTrackOrientation: true, isTrackPosition: true)
                    isPresentedLobby.wrappedValue = false
                    isPresentedLobby.update()
                }

                Text("A test room through the lens pass, tracked by ARKit. Tap to recenter; hold 1 s to come back here.")
                    .fontWeight(.light)
            }

            Section("Lenses") {
                SettingSlider(title: "k1", value: $vr.k1, range: 0...1, step: 0.01, format: "%.2f")
                SettingSlider(title: "k2", value: $vr.k2, range: 0...1, step: 0.01, format: "%.2f")
                SettingSlider(title: "Screen to lens (mm)", value: $vr.screenToLensMm, range: 20...70, step: 0.5, format: "%.1f")
                SettingSlider(title: "FOV limit per side (°)", value: $vr.fovLimitDeg, range: 30...70, step: 1, format: "%.0f")
                SettingSlider(title: "IPD (mm)", value: $vr.ipdMm, range: 54...74, step: 0.5, format: "%.1f")
                SettingSlider(title: "Lens height offset (mm)", value: $vr.lensYOffsetMm, range: -10...10, step: 0.5, format: "%.1f")
                Button("Reset to defaults") { vr = VRSettings() }
            }

            Section("Head") {
                SettingSlider(title: "Eye height (m)", value: $vr.eyeHeightM, range: 1.0...2.0, step: 0.05, format: "%.2f")
                Toggle("Reprojection", isOn: Binding(get: { vr.reprojection > 0.5 }, set: { vr.reprojection = $0 ? 1 : 0 }))
                Toggle("120 Hz display (off: 60 Hz, cooler)", isOn: Binding(get: { vr.highRefresh > 0.5 }, set: { vr.highRefresh = $0 ? 1 : 0 }))
                SettingSlider(title: "Test mode: simulated latency (ms)", value: $vr.latencyMs, range: 0...200, step: 10, format: "%.0f")
            }

            Section("AR passthrough") {
                Toggle("Camera behind the image", isOn: Binding(get: { vr.passthrough > 0.5 }, set: { vr.passthrough = $0 ? 1 : 0 }))
                Picker("Depth", selection: Binding(get: { Int(vr.lidarDepth) }, set: { vr.lidarDepth = Float($0) })) {
                    Text("Fixed 1.5 m").tag(0)
                    Text("LiDAR average").tag(1)
                    Text("LiDAR stereo").tag(2)
                }
                Picker("In front of virtual", selection: Binding(get: { Int(vr.occlusion) }, set: { vr.occlusion = Float($0) })) {
                    Text("Nothing").tag(0)
                    Text("People & hands").tag(1)
                    Text("LiDAR (fuzzy)").tag(2)
                }
                SettingSlider(title: "Stream: hands closer than (m) cut through", value: $vr.handDistanceM, range: 0.3...1.5, step: 0.05, format: "%.2f")
                Picker("See-through color (stream)", selection: Binding(get: { Int(vr.keyMode) }, set: { vr.keyMode = Float($0) })) {
                    Text("None").tag(0)
                    Text("Black").tag(1)
                    Text("Magenta").tag(2)
                }
                SettingSlider(title: "Key tolerance", value: $vr.keyTolerance, range: 0...0.3, step: 0.01, format: "%.2f")
                Text("Test mode shows a floating panel and two balls over the camera. With the stream, pixels in the see-through color show the room (issue #5).")
                    .fontWeight(.light)
            }
            
            Section("Server") {
                ListItem(title: "IP", content: "\(eventHandler.ipAddr)")
                ListItem(title: "Hostname", content: "\(eventHandler.hostname)")
            }
            
            Section("Tracking") {
                Toggle("Orientation", isOn: !$viewModel.isDontTrackOrientation)
                Toggle("Position", isOn: !$viewModel.isDontTrackPosition)
            }
        }
        .onAppear {
            viewModel.loadSettings()
        }
    }
}
