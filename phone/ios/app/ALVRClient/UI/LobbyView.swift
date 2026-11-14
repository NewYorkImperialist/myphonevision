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
    var eyeHeightM: Float = 1.65       // head height above the floor after a recenter
    var latencyMs: Float = 0           // test mode only: render the room this late, like the stream
    var reprojection: Float = 1        // 1 on, 0 off
    var highRefresh: Float = 1         // 1: 120 Hz display, 0: 60 Hz (cooler)

    var displayHz: Int { highRefresh > 0.5 ? 120 : 60 }

    static let screenWidthMm: Float = 144.8   // iPhone 16 Pro: 2622 x 1206 px at 460 ppi
    static let screenHeightMm: Float = 66.6
    static var current = VRSettings.load()

    private static let keys = ["k1", "k2", "ipdMm", "screenToLensMm", "lensYOffsetMm", "eyeHeightM", "latencyMs", "reprojection", "highRefresh"]
    private static let paths: [WritableKeyPath<VRSettings, Float>] = [\.k1, \.k2, \.ipdMm, \.screenToLensMm, \.lensYOffsetMm, \.eyeHeightM, \.latencyMs, \.reprojection, \.highRefresh]

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

    /// Per eye (left, right): tangents of the left, right, up and down edges of what
    /// the eye sees through its lens, with the same lens model as the shader (left
    /// and down negative). ALVR renders each eye with this FOV.
    func eyeFovTangents() -> [SIMD4<Float>] {
        func seen(_ d: Float) -> Float {
            let r2 = d * d
            return max(-2.5, min(2.5, d * (1 + k1 * r2 + k2 * r2 * r2)))
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

/// The phone's IPv4 addresses, for adding it by hand in the ALVR dashboard (iOS blocks
/// ALVR's mDNS discovery without the multicast entitlement). Over USB, Personal Hotspot
/// puts the phone on a `bridge` interface, usually 172.20.10.1.
struct PhoneAddress: Identifiable, Equatable {
    let name: String
    let address: String
    var id: String { name + address }
    var label: String {
        if name.hasPrefix("bridge") { return "USB / Personal Hotspot" }
        if name == "en0" { return "Wi-Fi" }
        return name
    }

    static func current() -> [PhoneAddress] {
        var list: [PhoneAddress] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard flags & (IFF_UP | IFF_RUNNING) == (IFF_UP | IFF_RUNNING), flags & IFF_LOOPBACK == 0,
                  let sa = ptr.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ptr.pointee.ifa_name)
            // Cellular and VPN tunnels can't be reached from the laptop.
            if name.hasPrefix("pdp_ip") || name.hasPrefix("utun") || name.hasPrefix("ipsec") { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            list.append(PhoneAddress(name: name, address: String(cString: host)))
        }
        // USB hotspot first: it's the one to use when it's there.
        return list.sorted { ($0.name.hasPrefix("bridge") ? 0 : 1) < ($1.name.hasPrefix("bridge") ? 0 : 1) }
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
    @State private var addresses: [PhoneAddress] = []

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

                Text("Connects to ALVR v21.0.0-dev14 on the laptop (the same server as the Pixel). Put the headset on facing forward; tap to recenter, hold 1 s to come back here.")
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

            Section("Head") {
                SettingSlider(title: "Eye height (m)", value: $vr.eyeHeightM, range: 1.0...2.0, step: 0.05, format: "%.2f")
                Toggle("Reprojection", isOn: Binding(get: { vr.reprojection > 0.5 }, set: { vr.reprojection = $0 ? 1 : 0 }))
                Toggle("120 Hz display (off: 60 Hz, cooler)", isOn: Binding(get: { vr.highRefresh > 0.5 }, set: { vr.highRefresh = $0 ? 1 : 0 }))
                SettingSlider(title: "Test mode: simulated latency (ms)", value: $vr.latencyMs, range: 0...200, step: 10, format: "%.0f")
            }
            
            Section {
                ListItem(title: "Hostname", content: "\(eventHandler.hostname)")
                ForEach(addresses) { a in
                    ListItem(title: a.label, content: a.address)
                }
                if addresses.isEmpty {
                    Text("No network. Plug in USB with Personal Hotspot on, or join Wi-Fi.").fontWeight(.light)
                }
            } header: {
                Text("Add this phone in the ALVR dashboard")
            } footer: {
                Text("ALVR dashboard → Add device manually: the hostname and one IP. Over USB, use the USB / Personal Hotspot IP (Settings → Personal Hotspot → Allow Others to Join; Wi-Fi off on both ends).")
            }
            
            Section("Tracking") {
                Toggle("Orientation", isOn: !$viewModel.isDontTrackOrientation)
                Toggle("Position", isOn: !$viewModel.isDontTrackPosition)
            }
        }
        .onAppear {
            viewModel.loadSettings()
            addresses = PhoneAddress.current()
        }
        // Interfaces come and go (USB cable, hotspot, Wi-Fi), so keep the list fresh.
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            let now = PhoneAddress.current()
            if now != addresses { addresses = now }
        }
    }
}
