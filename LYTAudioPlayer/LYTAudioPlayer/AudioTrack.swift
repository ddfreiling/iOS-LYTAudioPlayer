//
//  AudioTrack.swift
//  AudioQueuePlayer
//
//  Created by Lyt on 10/05/16.
//  Copyright © 2016 Lyt. All rights reserved.
//

import Foundation

@objc open class LYTAudioTrack : NSObject {
    
    open var url: URL
    open var title: String
    open var artist: String
    open var album: String
    open var albumArtUrl: URL?
    open var albumArtCachedImage: UIImage? // for storing once downloaded
    
    public init(url: URL, title: String, artist: String, album: String, albumArtUrl: URL?) {
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtUrl = albumArtUrl
    }
}
