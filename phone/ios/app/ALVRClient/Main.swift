//
//  File.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 22.02.2024.
//

import SwiftUI

@main
struct Main: App {
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
