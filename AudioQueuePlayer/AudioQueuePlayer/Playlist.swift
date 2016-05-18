//
//  Playlist.swift
//  AudioQueuePlayer
//
//  Created by Lyt on 10/05/16.
//  Copyright © 2016 Lyt. All rights reserved.
//

import Foundation

public class Playlist {
    
    public var tracks: [AudioTrack] = [AudioTrack]()
    
    public init() {
        
    }
    
    public func addTrack(audioTrack: AudioTrack) {
        tracks.append(audioTrack)
    }
    
    public var trackCount: Int {
        get {
            return tracks.count
        }
    }
}