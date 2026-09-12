//
//  MinimalistMusicPlayerView.swift
//  CrossFadeMusicPlayer
//
//  Created by Darshan Dodia on 13/03/26.
//

import SwiftUI

struct MinimalistMusicPlayerView: View {
    // The main view initializes and OWNS the view model
    @StateObject private var viewModel = AudioPlayerViewModel()
    
    // MARK: - UI & Drag State
    
    @State private var isAnimating: Bool = false
    @State private var showingQueue = false
    
    // Animation States for Crossfade
    @State private var toneArmAngle: Double = 0.0
    @State private var recordFlipAngle: Double = 0.0
    @State private var recordScaleX: CGFloat = 1.0 // NEW: Tracks X-scale mirror
    
    // Seek bar state
    @State private var isDragging: Bool = false
    @State private var dragProgress: Double = 0.0
    
    // MARK: - Theme Colors
    
    let topCream = Color(red: 0.96, green: 0.93, blue: 0.86)
    let bottomTerracotta = Color(red: 0.85, green: 0.55, blue: 0.42)
    let recordOuter = Color(red: 0.77, green: 0.40, blue: 0.28)
    let darkBrown = Color(red: 0.25, green: 0.16, blue: 0.14)
    let goldenYellow = Color(red: 0.82, green: 0.61, blue: 0.20)
    
    // MARK: - Computed Track Info
    
    private var currentTrackName: String {
        guard viewModel.trackNames.indices.contains(viewModel.currentTrackIndex) else { return "No Tracks Found" }
        return viewModel.trackNames[viewModel.currentTrackIndex]
    }
    
    private var displayArtist: String {
        // Splits "Song - Artist" if formatted that way
        let components = currentTrackName.components(separatedBy: " - ")
        return components.first ?? currentTrackName
    }
    
    private var displayTitle: String {
        let components = currentTrackName.components(separatedBy: " - ")
        return components.count > 1 ? components[1] : "Unknown Track"
    }
    
    var body: some View {
        ZStack {
            // Background Gradient
            LinearGradient(
                gradient: Gradient(colors: [topCream, bottomTerracotta]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                
                // MARK: - Header (Queue Button)
                
                HStack {
                    Text("Crossfade Player")
                        .font(Font.title.bold())
                        .foregroundColor(darkBrown)
                    Spacer()
                    Button(action: {
                        showingQueue = true
                    }) {
                        Image(systemName: "list.bullet")
                            .font(.title2)
                            .foregroundColor(darkBrown)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 30)
                
                // MARK: - Record Player
                
                ZStack {
                    // Rotating Vinyl Record
                    ZStack {
                        // Outer Terracotta
                        Circle()
                            .fill(recordOuter)
                            .frame(width: 320, height: 320)
                        
                        // Middle Dark Brown
                        Circle()
                            .fill(darkBrown)
                            .frame(width: 240, height: 240)
                        
                        // Subtle Track Marker to make rotation visible
                        Rectangle()
                            .fill(topCream.opacity(0.9))
                            .frame(width: 35, height: 15)
                            .offset(x: 110, y: 0)
                            .rotationEffect(.degrees(isAnimating ? 360 : 0))
                            .animation(
                                isAnimating ? .linear(duration: 4).repeatForever(autoreverses: false) : .default,
                                value: isAnimating
                            )

                        // Inner Cream
                        Circle()
                            .fill(topCream)
                            .frame(width: 160, height: 160)
                    }
                    .scaleEffect(x: recordScaleX) // NEW: Counteracts the 3D mirror
                    .rotation3DEffect(.degrees(recordFlipAngle), axis: (x: 0, y: 1, z: 0)) // Coin flip effect
                    
                    // Static Tonearm (Now Animatable)
                    ToneArmShape()
                        .fill(goldenYellow)
                        .frame(width: 320, height: 320)
                        // Using UnitPoint(0.95, -0.10) to match the starting coordinates of the ToneArmShape
                        .rotationEffect(.degrees(toneArmAngle), anchor: UnitPoint(x: 0.95, y: -0.10))
                }
                .padding(.top, 10)
                
                // MARK: - Track Info
                
                VStack(spacing: 8) {
                    Text(displayTitle)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(darkBrown)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Text(displayArtist)
                        .font(.title3)
                        .foregroundColor(darkBrown)
                    
                    Rectangle()
                        .fill(darkBrown)
                        .frame(width: 150, height: 1)
                        .padding(.top, 12)
                }
                
                // MARK: - Playback Controls
                
                HStack(spacing: 40) {
                    Button(action: {
                        viewModel.goToPreviousOrRestart()
                    }) {
                        Image(systemName: "backward.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 45, height: 30)
                            .foregroundColor(darkBrown)
                    }
                    
                    Button(action: {
                        viewModel.togglePlayPause()
                    }) {
                        ZStack {
                            Circle()
                                .fill(darkBrown)
                                .frame(width: 85, height: 85)
                            
                            Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 45, height: 30)
                                .foregroundColor(topCream)
                        }
                    }
                    
                    Button(action: {
                        viewModel.skipToNext()
                    }) {
                        Image(systemName: "forward.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 45, height: 30)
                            .foregroundColor(darkBrown)
                    }
                }
                
                // MARK: - Custom Interactive Seek Bar
                
                GeometryReader { geometry in
                    let activeProgress = isDragging ? dragProgress : (viewModel.trackDuration > 0 ? viewModel.currentTime / viewModel.trackDuration : 0)
                    
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(darkBrown)
                            .frame(height: 6)
                        
                        Rectangle()
                            .fill(recordOuter)
                            .frame(width: 25, height: 25)
                            .offset(x: max(0, min(geometry.size.width * activeProgress, geometry.size.width - 25)))
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        isDragging = true
                                        let newProgress = value.location.x / geometry.size.width
                                        dragProgress = min(max(newProgress, 0), 1)
                                    }
                                    .onEnded { value in
                                        let targetTime = dragProgress * viewModel.trackDuration
                                        viewModel.seek(to: targetTime)
                                        isDragging = false
                                    }
                            )
                    }
                    .frame(height: 25)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
                .frame(height: 30)
                .padding(.horizontal, 40)
                
                Spacer()
            }
        }
        .onAppear {
            viewModel.loadSongsFromBundle()
        }
        .onChange(of: viewModel.isPlaying) { _, playing in
            isAnimating = playing
        }
        // MARK: - The Choreography
        .onChange(of: viewModel.isCrossfading) { _, isCrossfading in
            if isCrossfading {
                // 1. Move tonearm off the record (0s -> 1.0s)
                withAnimation(.easeInOut(duration: 1.0)) {
                    toneArmAngle = 50.0
                }
                
                // 2. Flip the vinyl over (1.5s -> 3.0s)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    guard viewModel.isCrossfading else { return } // Safety check
                    withAnimation(.easeInOut(duration: 1.5)) {
                        recordFlipAngle -= 180.0
                    }
                    
                    // NEW: Secretly flip the X scale when the record is exactly edge-on (0.75s).
                    // We don't guard this block, so if the flip animation starts, this is guaranteed to execute.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                        recordScaleX *= -1.0
                    }
                }
                
                // 3. Move tonearm back as new track takes over (3.5s -> 4.5s)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                    guard viewModel.isCrossfading else { return }
                    withAnimation(.easeInOut(duration: 1.0)) {
                        toneArmAngle = 0.0
                    }
                }
            } else {
                // If user skips manually, snap the arm back.
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    toneArmAngle = 0.0
                }
            }
        }
        .sheet(isPresented: $showingQueue) {
            // Present the exact same QueueView we built earlier
            QueueView(viewModel: viewModel)
        }
    }
}

// MARK: - Custom Shape for Tone Arm

struct ToneArmShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let width = rect.width
        let height = rect.height
        
        let startX = width * 0.95
        let startY = height * -0.10
        let tipX = width * 0.58
        let tipY = height * 0.42
        
        path.move(to: CGPoint(x: startX, y: startY))
        path.addLine(to: CGPoint(x: startX + 20, y: startY + 15))
        path.addLine(to: CGPoint(x: tipX + 10, y: tipY + 18))
        path.addLine(to: CGPoint(x: tipX, y: tipY))
        path.addLine(to: CGPoint(x: tipX - 6, y: tipY - 8))
        path.addLine(to: CGPoint(x: startX - 15, y: startY - 5))
        
        path.closeSubpath()
        return path
    }
}

#Preview {
    MinimalistMusicPlayerView()
}
