//
//  Playlist.swift
//  AudioQueuePlayer
//
//  Created by Lyt on 10/05/16.
//  Copyright © 2016 Lyt. All rights reserved.
//

import Foundation

@objc open class LYTPlaylist : NSObject {
    
    open var tracks: [LYTAudioTrack] = [LYTAudioTrack]()
    
    public override init() {
        
    }
    
    open func addTrack(_ audioTrack: LYTAudioTrack) {
        tracks.append(audioTrack)
    }
    
    open var trackCount: Int {
        get {
            return tracks.count
        }
    }
}
