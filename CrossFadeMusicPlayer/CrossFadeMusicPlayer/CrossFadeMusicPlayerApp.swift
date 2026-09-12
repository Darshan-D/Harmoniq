//
//  CrossFadeMusicPlayerApp.swift
//  CrossFadeMusicPlayer
//
//  Created by Darshan Dodia on 24/02/26.
//

import AVFoundation
import SwiftUI

@main
struct CrossFadeMusicPlayerApp: App {
    
    init() {
        configureAudioSession()
    }
    
    var body: some Scene {
        WindowGroup {
            MinimalistMusicPlayerView()
        }
    }
    
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // .playback is the magic category. It tells iOS:
            // "I am a media app. Play even if the silent switch is on, and keep me alive in the background."
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            
            print("Audio session successfully configured for background playback.")
        } catch {
            print("Failed to set up audio session: \(error.localizedDescription)")
        }
    }
}
