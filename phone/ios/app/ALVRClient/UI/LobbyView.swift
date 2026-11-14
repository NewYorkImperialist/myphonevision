//
//  LobbyView.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 26.02.2024.
//

import SwiftUI

/// Lens and screen geometry for the lens pass, saved on the phone.
/// Defaults come from phone/ios/README.md; tune k1 by eye in test mode.
struct VRSettings {
    var k1: Float = 0.24
    var k2: Float = 0.30
    var ipdMm: Float = 63
    var screenToLensMm: Float = 42.5   // lens_f - focus_back_off (45 - 2.5 until the lenses are measured)
    var lensYOffsetMm: Float = 0       // lens centers above (+) or below (-) the screen center

    static let screenWidthMm: Float = 144.8   // iPhone 16 Pro: 2622 px at 460 ppi
    static var current = VRSettings.load()

    private static let keys = ["k1", "k2", "ipdMm", "screenToLensMm", "lensYOffsetMm"]
    private static let paths: [WritableKeyPath<VRSettings, Float>] = [\.k1, \.k2, \.ipdMm, \.screenToLensMm, \.lensYOffsetMm]

    static func load() -> VRSettings {
        var s = VRSettings()
        for (key, path) in zip(keys, paths) {
            if let v = UserDefaults.standard.object(forKey: "vr." + key) as? Float { s[keyPath: path] = v }
        }
        return s
    }

    func save() {
        for (key, path) in zip(VRSettings.keys, VRSettings.paths) {
            UserDefaults.standard.set(self[keyPath: path], forKey: "vr." + key)
        }
        VRSettings.current = self
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

                Text("After pressing the start button, the device should lie on the table in a horizontal position.")
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
                SettingSlider(title: "Screen to lens (mm)", value: $vr.screenToLensMm, range: 25...70, step: 0.5, format: "%.1f")
                SettingSlider(title: "IPD (mm)", value: $vr.ipdMm, range: 54...74, step: 0.5, format: "%.1f")
                SettingSlider(title: "Lens height offset (mm)", value: $vr.lensYOffsetMm, range: -10...10, step: 0.5, format: "%.1f")
                Button("Reset to defaults") { vr = VRSettings() }
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
