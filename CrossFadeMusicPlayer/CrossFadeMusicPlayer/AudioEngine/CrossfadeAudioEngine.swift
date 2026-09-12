//
//  CrossfadeAudioEngine.swift
//  CrossFadeMusicPlayer
//
//  Created by Darshan Dodia.
//

import AVFoundation
import Combine
import Foundation
import Dispatch

class CrossfadeAudioEngine: ObservableObject {

    // MARK: - Core Architecture

    private let engine = AVAudioEngine()

    // Dual-Deck Node Graph
    private let playerA = AVAudioPlayerNode()
    private let playerB = AVAudioPlayerNode()

    // The Dedicated EQ Nodes for DSP Volume Automation
    private let eqA = AVAudioUnitEQ(numberOfBands: 1)
    private let eqB = AVAudioUnitEQ(numberOfBands: 1)

    private let mixerA = AVAudioMixerNode()
    private let mixerB = AVAudioMixerNode()

    // MARK: - Published UI State

    @Published var currentIndex: Int = 0
    @Published var currentPlaybackTime: Double = 0.0
    @Published var trackDuration: Double = 1.0
    @Published var isPlaying: Bool = false
    @Published var isCrossfading: Bool = false

    // MARK: - Internal State
    //
    // Everything below is only ever read or mutated on `audioQueue`. User-facing
    // methods (togglePlayback, skipToNext, skipToPrevious, seek) hop onto that
    // queue before touching any of it, and so does the polling timer and the
    // file-preload work — one serial queue owns all of it, so there's no need
    // for locks.

    private var playlist: [URL] = []
    private var isDeckAActive = true
    private let crossfadeDuration: Double = 5.0

    // File and Time Management
    private var fileA: AVAudioFile?
    private var fileB: AVAudioFile?
    private var activeAudioFile: AVAudioFile? { isDeckAActive ? fileA : fileB }

    private var playbackToken = UUID()
    private var sampleRate: Double = 44100.0
    private var currentSeekOffset: Double = 0.0
    private var hasTriggeredOverlap = false

    // MARK: - Background Timer State

    private var audioPollingTimer: DispatchSourceTimer?
    // The single serial queue that owns all engine state (see note above).
    private let audioQueue = DispatchQueue(label: "com.crossfade.audioEngineQueue", qos: .userInteractive)

    init() {
        setupEngine()
        setupInterruptionHandling()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopAudioPolling()
    }

    // MARK: - Setup & Routing

    private func setupEngine() {
        engine.attach(playerA)
        engine.attach(eqA)
        engine.attach(mixerA)

        engine.attach(playerB)
        engine.attach(eqB)
        engine.attach(mixerB)

        // Chain Deck A: Player -> EQ -> Mixer -> Main
        engine.connect(playerA, to: eqA, format: nil)
        engine.connect(eqA, to: mixerA, format: nil)
        engine.connect(mixerA, to: engine.mainMixerNode, format: nil)

        // Chain Deck B: Player -> EQ -> Mixer -> Main
        engine.connect(playerB, to: eqB, format: nil)
        engine.connect(eqB, to: mixerB, format: nil)
        engine.connect(mixerB, to: engine.mainMixerNode, format: nil)

        engine.prepare()
        do { try engine.start() } catch { print("Engine start failed: \(error)") }
    }

    private func setupInterruptionHandling() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification, object: nil
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        // Only react to interruptions starting (e.g. a phone call). We don't
        // auto-resume on `.ended` — silently resuming audio the user didn't
        // ask to resume would be surprising; they can just hit play again.
        if type == .began {
            pauseForInterruption()
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        // e.g. headphones unplugged — pause instead of suddenly blasting audio
        // out of the speaker.
        if reason == .oldDeviceUnavailable {
            pauseForInterruption()
        }
    }

    private func pauseForInterruption() {
        audioQueue.async { [weak self] in
            guard let self = self, self.isPlaying else { return }
            self.togglePlaybackLocked()
        }
    }

    func loadPlaylist(_ urls: [URL]) {
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            self.playlist = urls
            guard !urls.isEmpty else { return }

            // Load Track 1 into Active Deck
            self.prepareDeck(for: 0, deck: self.playerA, isPreload: false)
            // Pre-load Track 2 into Standby Deck
            if urls.count > 1 {
                self.prepareDeck(for: 1, deck: self.playerB, isPreload: true)
            }
        }
    }

    // MARK: - Deck Preparation
    // Always called on `audioQueue`, including preload calls — keeping file
    // loading on the same serial queue as everything else avoids racing on
    // `fileA`/`fileB` while still staying off the main thread.

    private func prepareDeck(for index: Int, deck: AVAudioPlayerNode, isPreload: Bool) {
        guard index < playlist.count else { return }

        do {
            let file = try AVAudioFile(forReading: playlist[index])
            self.sampleRate = file.processingFormat.sampleRate

            if deck == playerA { self.fileA = file }
            if deck == playerB { self.fileB = file }

            // Set initial EQ volume to full (0.0 dB)
            let targetEQ = deck == playerA ? eqA : eqB
            scheduleGain(on: targetEQ, to: 0.0)

            if !isPreload {
                self.currentSeekOffset = 0.0
                self.hasTriggeredOverlap = false

                self.trackDuration = Double(file.length) / self.sampleRate
                self.isCrossfading = false
            }

            let token = UUID()
            if !isPreload { self.playbackToken = token }

            deck.scheduleFile(file, at: nil) { [weak self] in
                self?.handleTrackCompletion(completedIndex: index, token: token)
            }
        } catch {
            print("Failed to read Audio File: \(error)")
        }
    }

    // MARK: - User Controls
    //
    // Each of these hops onto `audioQueue` and defers to a "Locked" sibling
    // that assumes it's already running there.

    func togglePlayback() {
        audioQueue.async { [weak self] in self?.togglePlaybackLocked() }
    }

    private func togglePlaybackLocked() {
        let activePlayer = isDeckAActive ? playerA : playerB

        if isPlaying {
            activePlayer.pause()
            stopAudioPolling()
        } else {
            activePlayer.play()
            startAudioPolling()
        }
        isPlaying.toggle()
    }

    func skipToNext() {
        audioQueue.async { [weak self] in self?.skipToNextLocked() }
    }

    private func skipToNextLocked() {
        let activePlayer = isDeckAActive ? playerA : playerB
        let standbyPlayer = isDeckAActive ? playerB : playerA

        // Invalidate token so it doesn't trigger the natural end-of-track handler
        self.playbackToken = UUID()
        activePlayer.stop()

        executeHandoff()

        if isPlaying {
            standbyPlayer.play()
            startAudioPolling()
        }
    }

    func skipToPrevious() {
        audioQueue.async { [weak self] in self?.skipToPreviousLocked() }
    }

    private func skipToPreviousLocked() {
        // Nothing to go back to — just restart the current track.
        guard currentIndex > 0 else {
            seekLocked(to: 0)
            return
        }

        let activePlayer = isDeckAActive ? playerA : playerB
        let standbyPlayer = isDeckAActive ? playerB : playerA

        self.playbackToken = UUID()
        activePlayer.stop()
        standbyPlayer.stop()

        // Safe to set @Published state directly here: the ViewModel subscribes
        // via `.receive(on: RunLoop.main)`, so it gets re-marshaled to main
        // regardless of which thread set the value.
        currentIndex -= 1

        // Load the previous track straight into the active deck (hard cut,
        // same as skipping forward) and re-preload the new standby slot.
        prepareDeck(for: currentIndex, deck: activePlayer, isPreload: false)
        if currentIndex + 1 < playlist.count {
            prepareDeck(for: currentIndex + 1, deck: standbyPlayer, isPreload: true)
        }

        if isPlaying {
            activePlayer.play()
            startAudioPolling()
        }
    }

    func seek(to targetSeconds: Double) {
        audioQueue.async { [weak self] in self?.seekLocked(to: targetSeconds) }
    }

    private func seekLocked(to targetSeconds: Double) {
        let activePlayer = isDeckAActive ? playerA : playerB
        guard let file = activeAudioFile else { return }

        let targetFrame = AVAudioFramePosition(targetSeconds * sampleRate)
        let totalFrames = file.length

        guard targetFrame < totalFrames else {
            skipToNextLocked()
            return
        }

        self.playbackToken = UUID()
        activePlayer.stop()

        self.currentSeekOffset = targetSeconds
        self.currentPlaybackTime = targetSeconds

        // If we scrub backward out of the overlap zone, reset the trigger
        if trackDuration - targetSeconds > crossfadeDuration {
            self.hasTriggeredOverlap = false
            self.isCrossfading = false

            let standbyPlayer = isDeckAActive ? playerB : playerA
            standbyPlayer.stop()

            if currentIndex + 1 < playlist.count {
                prepareDeck(for: currentIndex + 1, deck: standbyPlayer, isPreload: true)
            }

            let activeEQ = isDeckAActive ? eqA : eqB
            scheduleGain(on: activeEQ, to: 0.0)
        }

        let remainingFrames = AVAudioFrameCount(totalFrames - targetFrame)
        let token = self.playbackToken

        activePlayer.scheduleSegment(file, startingFrame: targetFrame, frameCount: remainingFrames, at: nil) { [weak self] in
            self?.handleTrackCompletion(completedIndex: self?.currentIndex ?? 0, token: token)
        }

        if isPlaying {
            activePlayer.play()
            startAudioPolling()
        }
    }

    // MARK: - Background Polling

    private func startAudioPolling() {
        stopAudioPolling() // Clean up existing timer to avoid duplicates

        audioPollingTimer = DispatchSource.makeTimerSource(flags: [], queue: audioQueue)
        // Polling every 0.05 seconds gives 20 updates per second—plenty smooth for a UI progress bar
        // while being extremely lightweight on the CPU.
        audioPollingTimer?.schedule(deadline: .now(), repeating: 0.05)

        audioPollingTimer?.setEventHandler { [weak self] in
            self?.checkCrossfadeCondition()
        }

        audioPollingTimer?.resume()
    }

    private func stopAudioPolling() {
        audioPollingTimer?.cancel()
        audioPollingTimer = nil
    }

    private func checkCrossfadeCondition() {
        let activePlayer = isDeckAActive ? playerA : playerB

        guard let nodeTime = activePlayer.lastRenderTime,
              let playerTime = activePlayer.playerTime(forNodeTime: nodeTime) else { return }

        let playedSeconds = Double(playerTime.sampleTime) / playerTime.sampleRate
        let absoluteSeconds = currentSeekOffset + playedSeconds

        // 1. Update the UI Time
        self.currentPlaybackTime = min(absoluteSeconds, self.trackDuration)

        // 2. CHECK OVERLAP CONDITION: Are we in the final 5 seconds?
        let remainingSeconds = self.trackDuration - absoluteSeconds
        if remainingSeconds <= crossfadeDuration && remainingSeconds > 0 && !hasTriggeredOverlap {
            hasTriggeredOverlap = true

            // Only trigger overlap if there is actually a next song queued
            if currentIndex + 1 < playlist.count {
                self.isCrossfading = true
                executeOverlapSequence()
            }
        }
    }

    // MARK: - The Overlap & Crossfade Logic

    private func executeOverlapSequence() {
        let standbyDeck = isDeckAActive ? playerB : playerA
        let activeEQ = isDeckAActive ? eqA : eqB
        let standbyEQ = isDeckAActive ? eqB : eqA

        let fadeFrames = AUAudioFrameCount(crossfadeDuration * sampleRate)

        // Fade Out Active Deck
        scheduleGain(on: activeEQ, to: -80.0, rampFrames: fadeFrames)

        // Start Overlap
        standbyDeck.play()

        // Fade In Standby Deck
        scheduleGain(on: standbyEQ, to: -80.0)
        scheduleGain(on: standbyEQ, to: 0.0, rampFrames: fadeFrames)
    }

    private func executeHandoff() {
        currentIndex += 1
        isDeckAActive.toggle()
        currentSeekOffset = 0.0
        hasTriggeredOverlap = false
        isCrossfading = false

        let newStandbyDeck = isDeckAActive ? playerB : playerA

        let activeEQ = isDeckAActive ? eqA : eqB
        scheduleGain(on: activeEQ, to: 0.0)

        if let newFile = self.activeAudioFile {
            trackDuration = Double(newFile.length) / newFile.processingFormat.sampleRate
        }

        self.playbackToken = UUID()
        newStandbyDeck.stop()

        if currentIndex + 1 < playlist.count {
            // Stays on audioQueue rather than a separate background queue so it
            // can't race prepareDeck's reads/writes of fileA/fileB.
            audioQueue.async { [weak self] in
                guard let self = self else { return }
                self.prepareDeck(for: self.currentIndex + 1, deck: newStandbyDeck, isPreload: true)
            }
        }
    }

    private func handleTrackCompletion(completedIndex: Int, token: UUID) {
        audioQueue.async { [weak self] in
            guard let self = self, self.playbackToken == token else { return }

            if self.currentIndex == completedIndex {
                if !self.hasTriggeredOverlap {
                    let standbyDeck = self.isDeckAActive ? self.playerB : self.playerA
                    standbyDeck.play()
                }
                self.executeHandoff()
            }
        }
    }

    // MARK: - Gain Helper

    /// Schedules a volume ramp on an EQ's global gain, logging (rather than
    /// silently no-op'ing) if the AU doesn't expose the parameter.
    private func scheduleGain(on eq: AVAudioUnitEQ, to value: Float, rampFrames: AUAudioFrameCount = 0) {
        guard let gainParam = eq.auAudioUnit.parameterTree?.value(forKey: "globalGain") as? AUParameter else {
            print("CrossfadeAudioEngine: globalGain parameter unavailable — fade skipped")
            return
        }
        eq.auAudioUnit.scheduleParameterBlock(AUEventSampleTimeImmediate, rampFrames, gainParam.address, value)
    }
}
