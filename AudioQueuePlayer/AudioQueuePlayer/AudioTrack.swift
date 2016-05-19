//
//  AudioTrack.swift
//  AudioQueuePlayer
//
//  Created by Lyt on 10/05/16.
//  Copyright © 2016 Lyt. All rights reserved.
//

import Foundation

@objc public class LYTAudioTrack : NSObject {
    
    public var url: NSURL
    public var title: String
    public var artist: String
    public var album: String
    public var albumArtUrl: NSURL?
    public var albumArtCachedImage: UIImage? // for storing once downloaded
    
    public init(url: NSURL, title: String, artist: String, album: String, albumArtUrl: NSURL?) {
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtUrl = albumArtUrl
    }
}