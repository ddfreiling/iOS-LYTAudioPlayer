//
//  Playlist.swift
//  AudioQueuePlayer
//
//  Created by Lyt on 10/05/16.
//  Copyright © 2016 Lyt. All rights reserved.
//

import Foundation

@objc public class LYTPlaylist : NSObject {
    
    public var tracks: [LYTAudioTrack] = [LYTAudioTrack]()
    
    public override init() {
        
    }
    
    public func addTrack(audioTrack: LYTAudioTrack) {
        tracks.append(audioTrack)
    }
    
    public var trackCount: Int {
        get {
            return tracks.count
        }
    }
}