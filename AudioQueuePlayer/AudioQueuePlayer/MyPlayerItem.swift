//
//  MyPlayerItem.swift
//  AudioQueuePlayer
//
//  Created by Lyt on 18/05/16.
//  Copyright © 2016 Lyt. All rights reserved.
//

import Foundation
import AVFoundation

class MyPlayerItem : AVPlayerItem {
    
    private var myContext = 0
    
    let kLoadedTimeRangesKey = "loadedTimeRanges"
    let kPlaybackBufferEmptyKey = "playbackBufferEmpty"
    let kStatusKey = "status"
    
    override init(asset: AVAsset, automaticallyLoadedAssetKeys: [String]?) {
        super.init(asset: asset, automaticallyLoadedAssetKeys: automaticallyLoadedAssetKeys)
        subscribeToNotificationsAndObservers()
    }
    
    internal func subscribeToNotificationsAndObservers() {
        //self.addObserver(self, forKeyPath: kLoadedTimeRangesKey, options: , context: &myContext)
    }
}