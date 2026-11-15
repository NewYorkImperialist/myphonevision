//
//  File.swift
//  ALVRClient
//
//  Created by Viktor Varenik on 22.02.2024.
//

import SwiftUI

@main
struct Main: App {
    @State private var isLobbyPresented: Bool = true
    
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
                .fullScreenCover(isPresented: $isLobbyPresented, content: {
                    LobbyView(isPresentedLobby: $isLobbyPresented)
                        .background(.windowBackground)
                })
                .ignoresSafeArea()
        }
    }
}
