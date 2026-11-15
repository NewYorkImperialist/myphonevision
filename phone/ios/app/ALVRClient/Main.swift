//
//  File.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 22.02.2024.
//

import SwiftUI

/// Locks the UI to one landscape orientation so a head tilt can't flip the picture.
/// The admin page sets it: "upright" = the way the phone sits now; saved across launches.
final class OrientationLock: NSObject, UIApplicationDelegate {
    static var mask: UIInterfaceOrientationMask = {
        switch UserDefaults.standard.integer(forKey: "orientationLock") {
        case 1: return .landscapeLeft
        case 2: return .landscapeRight
        default: return .landscape
        }
    }()

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }

    private static var scene: UIWindowScene? { UIApplication.shared.connectedScenes.first as? UIWindowScene }

    private static func apply(_ m: UIInterfaceOrientationMask, saved: Int) {
        mask = m
        UserDefaults.standard.set(saved, forKey: "orientationLock")
        guard let scene else { return }
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: m)) { _ in }
        // The head axes follow the UI orientation; make the tracker re-read it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NotificationCenter.default.post(name: UIDevice.orientationDidChangeNotification, object: nil)
        }
    }

    /// Whichever landscape the phone is physically in now becomes the locked, upright one.
    static func lockUprightNow() {
        DispatchQueue.main.async {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            let current = scene?.interfaceOrientation
            let left: Bool
            switch UIDevice.current.orientation {
            case .landscapeLeft: left = false          // device left = UI landscape-right
            case .landscapeRight: left = true
            default: left = current == .landscapeLeft  // flat or unknown: keep what's on screen
            }
            apply(left ? .landscapeLeft : .landscapeRight, saved: left ? 1 : 2)
        }
    }

    static func flip() {
        DispatchQueue.main.async {
            let left = scene?.interfaceOrientation != .landscapeLeft
            apply(left ? .landscapeLeft : .landscapeRight, saved: left ? 1 : 2)
        }
    }

    static func unlock() {
        DispatchQueue.main.async { apply(.landscape, saved: 0) }
    }
}

@main
struct Main: App {
    @UIApplicationDelegateAdaptor(OrientationLock.self) var orientationLock
    @State private var isLobbyPresented: Bool = false   // opens straight into the sword game; hold 1 s for settings
    
    var body: some Scene {
        WindowGroup {
            MetalView()
                // Tap: recenter. Hold 1 s: back to the lobby (and out of test mode).
                .onTapGesture {
                    EventHandler.shared.recenter()
                    if Renderer.shared?.saberMode == true { Renderer.shared?.saberGame.recenter() }
                }
                .onLongPressGesture(minimumDuration: 1) {
                    Renderer.shared?.testMode = false
                    isLobbyPresented = true
                }
                .onAppear {   // the sword game is the default: start tracking and the controller link
                    UIApplication.shared.isIdleTimerDisabled = true
                    HandReceiver.shared.start()
                    EventHandler.shared.setWorldTrackingParams(isTrackOrientation: true, isTrackPosition: true)
                }
                .fullScreenCover(isPresented: $isLobbyPresented, content: {
                    LobbyView(isPresentedLobby: $isLobbyPresented)
                        .background(.windowBackground)
                })
                .ignoresSafeArea()
        }
    }
}
