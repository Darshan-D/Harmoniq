//
//  QueueView.swift
//  CrossFadeMusicPlayer
//
//  Created by Darshan Dodia on 24/02/26.
//

import SwiftUI

struct QueueView: View {
    // 4. Receives the view model, does NOT initialize a new one
    @ObservedObject var viewModel: AudioPlayerViewModel
    
    var body: some View {
        NavigationView {
            List {
                // Safely enumerate through the track names
                ForEach(Array(viewModel.trackNames.enumerated()), id: \.offset) { index, name in
                    HStack(spacing: 16) {
                        // Show an active speaker icon for the currently playing track
                        if index == viewModel.currentTrackIndex {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                        } else {
                            // Show a generic music note for other tracks
                            Image(systemName: "music.note")
                                .foregroundColor(.gray)
                                .frame(width: 24)
                        }
                        
                        // Display the track name, bolding the active one
                        Text(name)
                            .font(.system(size: 16, weight: index == viewModel.currentTrackIndex ? .bold : .regular))
                            .foregroundColor(index == viewModel.currentTrackIndex ? .primary : .secondary)
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    // Optional: Make the whole row tappable in the future
                    .contentShape(Rectangle())
                }
            }
            .navigationTitle("Up Next")
            .listStyle(PlainListStyle())
        }
    }
}
