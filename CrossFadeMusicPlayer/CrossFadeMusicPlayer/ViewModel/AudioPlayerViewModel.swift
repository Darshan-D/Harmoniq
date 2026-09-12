//
//  AudioPlayerViewModel.swift
//  CrossFadeMusicPlayer
//
//  Created by Darshan Dodia on 24/02/26.
//

import SwiftUI
import Combine
import AVFoundation

// A simple model for all local tracks
struct Track: Identifiable {
    let id = UUID()
    let title: String
    let artist: String
    let filename: String
}

class AudioPlayerViewModel: ObservableObject {
    private let engine = CrossfadeAudioEngine()
    private var cancellables = Set<AnyCancellable>()
    
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0.0
    @Published var currentTrackIndex: Int = 0
    @Published var trackDuration: Double = 180.0
    @Published var isCrossfading: Bool = false
    
    // Expose the list of track names to the UI
    @Published var trackNames: [String] = []
    
    init() {
        setupBindings()
    }
    
    private func setupBindings() {
        engine.$isPlaying
            .receive(on: RunLoop.main)
            .sink { [weak self] playing in self?.isPlaying = playing }
            .store(in: &cancellables)
        
        engine.$currentPlaybackTime
            .receive(on: RunLoop.main)
            .sink { [weak self] time in self?.currentTime = time }
            .store(in: &cancellables)
        
        engine.$currentIndex
            .receive(on: RunLoop.main)
            .sink { [weak self] index in self?.currentTrackIndex = index }
            .store(in: &cancellables)
        
        engine.$trackDuration
            .receive(on: RunLoop.main)
            .sink { [weak self] duration in
                // Prevent SwiftUI slider crash by ensuring duration is > 0
                self?.trackDuration = duration > 0 ? duration : 1.0
            }
            .store(in: &cancellables)
            
        // NEW: Bind crossfade state
        engine.$isCrossfading
            .receive(on: RunLoop.main)
            .sink { [weak self] crossfading in self?.isCrossfading = crossfading }
            .store(in: &cancellables)
    }
    
    func loadSongsFromBundle() {
        let songNames = [
            "Red Hot Chili Peppers - Snow (Hey Oh)",
            "Arijit Singh - Bekhayali",
            "Michael Jackson - Billie Jean",
            "ACDC - Highway to Hell",
        ]

        // Resolve each name to a URL first, and only keep names whose file
        // actually exists — this keeps trackNames and the URLs handed to the
        // engine aligned by index. (Previously, a missing file would drop the
        // URL but leave the name in trackNames, throwing every later index
        // in the queue out of sync with the track actually playing.)
        var resolvedNames: [String] = []
        var urls: [URL] = []
        for name in songNames {
            let url = Bundle.main.url(forResource: name, withExtension: "flac")
                ?? Bundle.main.url(forResource: name, withExtension: "mp3")
                ?? Bundle.main.url(forResource: name, withExtension: "wav")

            if let url = url {
                resolvedNames.append(name)
                urls.append(url)
            } else {
                print("Could not find: \(name)")
            }
        }

        self.trackNames = resolvedNames

        if !urls.isEmpty {
            engine.loadPlaylist(urls)
        }
    }
    
    // MARK: - User Intents
    func togglePlayPause() {
        engine.togglePlayback()
    }
    
    func skipToNext() {
        engine.skipToNext()
    }

    /// Mirrors standard media-player behavior: restart the current track if
    /// it's already played more than a few seconds, otherwise jump back to
    /// the previous track.
    func goToPreviousOrRestart() {
        if currentTime > 3.0 {
            engine.seek(to: 0)
        } else {
            engine.skipToPrevious()
        }
    }

    func seek(to time: Double) {
        engine.seek(to: time)
    }
}
