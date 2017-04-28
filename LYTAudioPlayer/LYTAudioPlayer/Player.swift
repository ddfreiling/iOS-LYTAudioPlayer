//
//  LYTPlayer.swift
//  AudioQueuePlayer
//
//  Created by Lyt on 10/05/16.
//  Copyright © 2016 Lyt. All rights reserved.
//

import Foundation
import AudioToolbox
import AVFoundation
import MediaPlayer
// FIXME: comparison operators with optionals were removed from the Swift Standard Libary.
// Consider refactoring the code to use the non-optional operators.
fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

// FIXME: comparison operators with optionals were removed from the Swift Standard Libary.
// Consider refactoring the code to use the non-optional operators.
fileprivate func >= <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l >= r
  default:
    return !(lhs < rhs)
  }
}


@objc public enum LYTPlayerState : UInt {
    case buffering = 0
    case playing = 1
    case paused = 2
    case stopped = 3
    case waitingForConnection = 4
    case failed = 5
    case ready = 6
}
extension LYTPlayerState: Equatable { }

public typealias Callback = () -> Void

@objc public protocol LYTPlayerDelegate: NSObjectProtocol {
    func didChangeStateFrom( _ from: LYTPlayerState, to: LYTPlayerState )
    func didFinishPlayingTrack( _ track: LYTAudioTrack )
    func didFindDuration( _ durationSeconds: Double, forTrack track: LYTAudioTrack )
    func didUpdateBufferedDuration( _ bufferedDuration: Double, forTrack track: LYTAudioTrack )
    func didChangeToTrack( _ track: LYTAudioTrack )
    func didEncounterError( _ error: NSError )
}

@objc open class LYTPlayer : NSObject {
    
    var audioPlayer = AVQueuePlayer()
    var authorizationFailedCallback: Callback?
    var currentPlaylist: LYTPlaylist?
    
    open var currentPlaylistIndex: Int = 0
    
    let observerManager = ObserverManager() // For KVO - see: https://github.com/timbodeit/ObserverManager
    
    open weak var delegate: LYTPlayerDelegate?
    open static let sharedInstance = LYTPlayer()
    
    fileprivate override init() {
        super.init()
        state = .stopped
        audioPlayer.actionAtItemEnd = .advance
        configureRemoteControlEvents()
        NotificationCenter.default.addObserver(self, selector: #selector(LYTPlayer.audioSessionInterrupted), name: NSNotification.Name.AVAudioSessionInterruption, object: AVAudioSession.sharedInstance())
        NotificationCenter.default.addObserver(self, selector: #selector(LYTPlayer.audioSessionRouteChanged), name: NSNotification.Name.AVAudioSessionRouteChange, object: AVAudioSession.sharedInstance())
    }
    
    deinit {
        stopPlayback(true)
    }
    
    // MARK: Readonly properties
    
    /// The current state of the player.
    open fileprivate(set) var state = LYTPlayerState.stopped {
        didSet {
            if state != oldValue || state == .waitingForConnection {
                onMainQueue() {
                    self.delegate?.didChangeStateFrom(oldValue, to: self.state)
                }
            }
        }
    }
    
    open var isPlaying: Bool {
        get {
            return (audioPlayer.rate != 0.0)
        }
    }
    
    open var currentTrack: LYTAudioTrack? {
        get {
            return currentPlaylist?.tracks[currentPlaylistIndex]
        }
    }
    
    open var currentTrackDuration: Double {
        get {
            if let item = self.audioPlayer.currentItem {
                return item.duration.seconds
            } else {
                return -1
            }
        }
    }
    
    // MARK: Public API
    open var playbackRate: Float {
        get {
            return audioPlayer.rate;
        }
        set {
            if (0.5 <= newValue && newValue <= 2) {
                audioPlayer.rate = newValue;
            } else {
                NSLog("invalid rate: \(newValue). Must be between 0.5 and 2.0");
            }
        }
    }
    
    open func loadPlaylist(_ playlist: LYTPlaylist, initialPlaylistIndex: Int) {
        onSerialQueue() {
            self.currentPlaylist = playlist
            self.currentPlaylistIndex = initialPlaylistIndex
            self.setupCurrentPlaylistIndex(self.currentPlaylistIndex)
        }
    }
    
    open func play() {
        guard let _ = currentPlaylist else { NSLog("NO currentPlaylist in \(#function)"); return }
        NSLog("\(#function)...")
        
        // Verify that we are ready to play....
        if ( audioPlayer.status == .readyToPlay ) {
            NSLog("LYTPlayer is READY")
            if let status = audioPlayer.currentItem?.status {
                switch status  {
                case AVPlayerItemStatus.readyToPlay :
                    NSLog("CurrentItem is READY")
                case AVPlayerItemStatus.failed :
                    NSLog("CurrentItem FAILED")
                default:
                    NSLog("CurrentItem is in an unknown state...")
                }
            } else {
                NSLog("LYTPlayer currentItem is in trouble: \(audioPlayer.currentItem.debugDescription)")
            }
        } else {
            NSLog("*** LYTPlayer is NOT READY : \(audioPlayer.error?.localizedDescription ?? "general error") ***")
            return
        }
        
        pausedByAudioSessionInterrupt = false
        setupAudioActive(true)
        audioPlayer.play()
        NSLog("LYTPlayer.play() status: \(currentStatus() )")
        state = .playing
    }
    
    func currentStatus() -> String {
        guard let currentPlaylist = currentPlaylist else { NSLog("NO currentPlaylist in \(#function)"); return "No current playlist" }
        let track = currentPlaylist.tracks[currentPlaylistIndex]
        let status = "'\(track.title)' (\(currentPlaylistIndex)/\(currentPlaylist.tracks.count)) \(track.url)"
        return status
    }
    
    open func pause() {
        NSLog("\(#function)...")
        audioPlayer.pause()
        // TODO: Register where we are so can continue where we stopped.
        setupAudioActive(false)
        state = .paused
    }
    
    open func stop() {
        self.stopPlayback(true);
    }
    
    fileprivate func stopPlayback(_ fullstop: Bool = false) {
        NSLog("\(#function)...")
        audioPlayer.pause() // AVPlayer does not have a stop method
        observerManager.deregisterAllObservers()
        audioPlayer.removeAllItems()
        state = .stopped
        if (fullstop) {
            currentPlaylistIndex = 0;
        }
    }
    
    open func nextAudioTrack(_ onCompletion: @escaping Callback) {
        guard let currentPlaylist = self.currentPlaylist else { NSLog("NO currentPlaylist in \(#function)"); return }
        if ( self.currentPlaylistIndex + 1 < currentPlaylist.trackCount ) {
            self.stopPlayback()
            let newPlaylistIndex = self.currentPlaylistIndex + 1
            NSLog("====> Skip to \(newPlaylistIndex)");
            self.setupCurrentPlaylistIndex( newPlaylistIndex ) {
                self.play()
                onCompletion()
            }
        } else {
            self.stopPlayback(true)
            onCompletion()
        }
    }
    
    open func previousAudioTrack(_ onCompletion: @escaping Callback) {
        self.setupCurrentPlaylistIndex( max(self.currentPlaylistIndex - 1, 0) ) {
            self.play()
            onCompletion()
        }
    }
    
    open var currentTime: Int {
        get {
            return lround(audioPlayer.currentTime().seconds * 1000)
        }
    }
    
    open func seekToTimeMilis(_ timeMilis: Int, onCompletion: @escaping Callback) {
        
        if (self.audioPlayer.currentItem == nil || self.audioPlayer.currentItem?.status != .readyToPlay) {
            return
        }
        
        onSerialQueue() {
            let newTime: CMTime = CMTimeMake(Int64(timeMilis), 1000)
            self.audioPlayer.seek(to: newTime, completionHandler: { success in
                self.updateNowPlayingInfo()
                onMainQueue() {
                    onCompletion()
                }
            }) 
        }
    }
    
    open func skipToPlaylistIndex(_ index: Int, onCompletion: @escaping Callback) {
        if (index < 0 || index >= self.currentPlaylist?.trackCount) {
            NSLog("\(#function) Invalid playlist index given: \(index)")
            return
        }
        let wasPlaying = self.isPlaying
        onSerialQueue() {
            self.setupCurrentPlaylistIndex(index) {
                if (wasPlaying) {
                    self.play();
                }
                onMainQueue() {
                    onCompletion()
                }
            }
        }
    }
    
    
    // MARK: Private
    
    // Return true if succesful.
    func setupAudioActive(_ active: Bool) -> Bool {
        NSLog("\(#function)( \(active) )...")
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(AVAudioSessionCategoryPlayback)
            try audioSession.setActive(active, with: .notifyOthersOnDeactivation ) // ??? Options
            return true
        } catch {
            NSLog("Error setting AudioSession !!!!!!!!!")
            // TODO: More error handling?
            return false
        }
    }
    
    func resetPlayer() {
        NotificationCenter.default.removeObserver(self)
        audioPlayer.pause()
        audioPlayer.removeAllItems()
        setupAudioActive(false)
    }
    
    func setupCurrentPlaylistIndex(_ playlistIndex: Int, onComplete: @escaping () -> () = {} ) {
        onSerialQueue() {
            guard let _ = self.currentPlaylist else { NSLog("NO currentPlaylist in \(#function)"); return }
            NSLog("setupCurrentAudioPart(\(playlistIndex)) ...")
            self.stopPlayback()
            self.setupAudioPlayerObservers()
            NSLog("setupCurrentAudioPart(\(playlistIndex)) - audioPlayer Initialized ...")
            self.currentPlaylistIndex = playlistIndex
            self.addItemToPlayerQueue(self.currentPlaylistIndex)
            onMainQueue() {
                onComplete()
            }
        }
    }
    
    // Adds a player item for a given playlist index to the play queue, and setup observers to automatically schedule the next.
    func addItemToPlayerQueue( _ playlistIndex: Int ) {
        guard let currentPlaylist = currentPlaylist else { NSLog("NO currentPlaylist in \(#function)"); return }
        let track = currentPlaylist.tracks[playlistIndex]
        NSLog("Add to Queue: \(track.url.lastPathComponent) from URL: \(track.url)")
        let asset = AVURLAsset(url: track.url as URL)
        let item = AVPlayerItem.init(asset: asset, automaticallyLoadedAssetKeys: ["duration","playable","tracks"]) // Asset keys that need to be present before the item is considered 'ready'
        self.setupPlayerItemObservers(item, itemPlaylistIndex: playlistIndex)
        self.audioPlayer.insert(item, after: nil) // append item to player queue
    }
    
    func setupPlayerItemObservers(_ item: AVPlayerItem, itemPlaylistIndex: Int) {
        NotificationCenter.default
            .addObserver(self, selector: #selector(finishedPlayingItem), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: item)
        let itemTrack: LYTAudioTrack = self.currentPlaylist!.tracks[itemPlaylistIndex]
        item.whenChanging("status", manager: observerManager ) { item in
            switch item.status {
            case .failed:
                NSLog("--> PlayerItem FAILED: \(item.asset.debugDescription)")
                //TODO: Handle this. resubmit?
            case .readyToPlay:
                NSLog("--> PlayerItem READY: \(item.asset.debugDescription)")
                self.state = .ready
                let nextPlaylistIndex = itemPlaylistIndex + 1
                if (nextPlaylistIndex < self.currentPlaylist?.trackCount) {
                    self.addItemToPlayerQueue(nextPlaylistIndex)
                }
                onMainQueue({
                    self.delegate?.didFindDuration(item.duration.seconds, forTrack: itemTrack)
                })
            case .unknown :
                NSLog("--> PlayerItem UNKNOWN status: \(item.asset.debugDescription)")
            }
            
            if let error = item.error {
                NSLog("--- Item Error: \(error.localizedDescription) reason: \(error.localizedDescription) - UserInfo: \(error._userInfo.debugDescription)")
                if ( error._code == NSURLErrorUserAuthenticationRequired ) { // Error codes: http://nshipster.com/nserror/
                    NSLog("*** Authentication Required !!!! ***")
                    // TODO: Callback to UI ? Deal with Authentication .....
                    // TODO: Remember where we where. Check if something is playing? (then what??)
                    self.pause() // TODO: Can we just resume when we come back???
                    self.authorizationFailedCallback?()
                } else {
                    NSLog("*** UNHANDLED ERROR !!!! ***")
                    // TODO: Deal with other item errors .......
                    onMainQueue({
                        self.delegate?.didEncounterError(error as NSError)
                    })
                }
            }
        }
        item.whenChanging("loadedTimeRanges", manager: observerManager) { item in
            let durationLoaded = self.durationLoadedOfItem(item)
            
            onMainQueue({
                self.delegate?.didUpdateBufferedDuration(durationLoaded, forTrack: itemTrack)
            })
        }
        item.whenChanging("playbackBufferEmpty", manager: observerManager) { item in
            NSLog("====================== Buffer empty for index \(itemPlaylistIndex)");
            self.state = .buffering
        }
    }
    
    func durationLoadedOfItem(_ item: AVPlayerItem) -> Double {
        //NSLog("-> Item has \(item.loadedTimeRanges.count) time ranges");
        let timeRange: CMTimeRange = item.loadedTimeRanges[0].timeRangeValue
        let loadedDuration: Double = CMTimeGetSeconds(timeRange.duration)
        return loadedDuration
    }
    
    func finishedPlayingItem() {
        // LYTPlayer finished playing track and will automatically start playing the next
        // Notify delegate and update the index of currently played track
        if let currentTrack = self.currentPlaylist?.tracks[currentPlaylistIndex] {
            onMainQueue({
                self.delegate?.didFinishPlayingTrack(currentTrack)
            })
        }
        self.currentPlaylistIndex += 1
    }
    
    // Now playing info is showed on the lock screen and the control center.
    func updateNowPlayingInfo() {
        guard let currentPlaylist = currentPlaylist else { NSLog("NO currentPlaylist in \(#function)"); return }
        NSLog("\(#function)...")
        let currentTrack: LYTAudioTrack = currentPlaylist.tracks[currentPlaylistIndex]
        
        NSLog("Updating NowPlayingInfo for: \(currentTrack.title)")
        let infoCenter = MPNowPlayingInfoCenter.default()
        var info = [String: AnyObject]()
        info[MPMediaItemPropertyMediaType] = MPMediaType.audioBook.rawValue as AnyObject // Not sure we need this, or what it does....
        info[MPMediaItemPropertyAlbumArtist] = currentTrack.artist as AnyObject
        info[MPMediaItemPropertyAlbumTitle] = currentTrack.album as AnyObject
        info[MPMediaItemPropertyTitle] = currentTrack.title as AnyObject
        info[MPNowPlayingInfoPropertyChapterNumber] = self.currentPlaylistIndex + 1 as AnyObject
        info[MPNowPlayingInfoPropertyChapterCount] = currentPlaylist.trackCount as AnyObject
        info[MPMediaItemPropertyAlbumTrackNumber] = self.currentPlaylistIndex + 1 as AnyObject
        info[MPNowPlayingInfoPropertyPlaybackRate] = self.audioPlayer.rate as AnyObject
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = self.audioPlayer.currentItem?.currentTime().seconds as AnyObject
        info[MPMediaItemPropertyPlaybackDuration] = self.audioPlayer.currentItem?.duration.seconds as AnyObject
        if let artImage = currentTrack.albumArtCachedImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(image: artImage)
        }
        infoCenter.nowPlayingInfo = info
        
        // Set artwork image async
        guard let imageUrl = currentTrack.albumArtUrl, currentTrack.albumArtCachedImage == nil else {
            NSLog("==> No album artwork url specified or already cached")
            return
        }
        onSerialQueue({
            guard let artworkImageData = try? Data(contentsOf: imageUrl),
                let artworkImage = UIImage(data: artworkImageData) else {
                    NSLog("Error downloading artwork image from: \(imageUrl.absoluteString)")
                    return
            }
            currentTrack.albumArtCachedImage = artworkImage
            NSLog("Artwork image size: %f.0 , %f.0", artworkImage.size.width, artworkImage.size.height)
            onMainQueue({
                NSLog("==> Setting MPMediaItemArtwork on main thread")
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(image: artworkImage)
                infoCenter.nowPlayingInfo = info
                NSLog("=== ARTWORK IMAGE SET ===")
            })
        })
    }
    
    func getArtworkImageFromUrl(_ imageUrlPath: String) -> UIImage? {
        guard let imageUrl = URL(string: imageUrlPath),
            let artworkImageData = try? Data(contentsOf: imageUrl),
            let artworkImage = UIImage(data: artworkImageData) else {
                NSLog("Error downloading artwork image from path: \(imageUrlPath)")
                return nil
        }
        return artworkImage
    }
    
    // -----------------------------------------------------------------------------------------------------
    // MARK: AVQueuePlayer Events
    
    var _timeObserver:AnyObject?
    var _boundarybserver:AnyObject?
    // Setup Observers for AVQueuePlayer
    func setupAudioPlayerObservers() {
        audioPlayer.whenChanging("currentItem", manager: observerManager) { player in
            NSLog("==> AudioPlayer new current item \(player.currentItem?.asset.debugDescription ?? "general error")")
            self.updateNowPlayingInfo()
            if let currentTrack: LYTAudioTrack = self.currentPlaylist?.tracks[self.currentPlaylistIndex] {
                onMainQueue({
                    self.delegate?.didChangeToTrack(currentTrack)
                })
            }
        }
        audioPlayer.whenChanging("status", manager: observerManager) { player in
            switch(player.status) {
            case .readyToPlay :
                NSLog("+++ LYTPlayer is ready to play!")
                self.state = .ready
            case .failed :
                NSLog("*** LYTPlayer Failed!")
                self.state = .failed
            case .unknown :
                NSLog("??? LYTPlayer is in UNKNOWN state ???")
            }
            
            self.updateNowPlayingInfo()
        }
        audioPlayer.whenChanging("rate", manager: observerManager) { player in
            let playingState = ( player.rate > 0 ? "Playing" : "Paused")
            NSLog("==> Got new rate \(player.rate) - LYTPlayer is \(playingState)" )
            self.updateNowPlayingInfo()
        }
    }
    
    func removeAudioPlayerObservers() {
        observerManager.deregisterObserversForObject(audioPlayer)
    }
    
    fileprivate var pausedByAudioSessionInterrupt = false
    
    // Called whenever we get interrupted (by f.ex. phone call, Alarm clock, etc.)
    func audioSessionInterrupted(_ notification: Notification)
    {
        guard let interruptTypeRaw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let interruptType = AVAudioSessionInterruptionType(rawValue: interruptTypeRaw) else {
                NSLog("*** AVAudioSessionInterruption: no type argument found")
                return
        }
        NSLog("*** AVAudioSessionInterruption: \(interruptType)")
        
        switch interruptType {
        case .began:
            pausedByAudioSessionInterrupt = true
            self.pause()
            break
        case .ended:
            if (!self.isPlaying && pausedByAudioSessionInterrupt) {
                self.play()
                pausedByAudioSessionInterrupt = false
            }
            break
        }
    }
    
    // Called whenever the audio route is changed (f.ex. switch to headset og AirPlay)
    // https://developer.apple.com/library/ios/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/HandlingAudioHardwareRouteChanges/HandlingAudioHardwareRouteChanges.html#//apple_ref/doc/uid/TP40007875-CH5-SW1
    func audioSessionRouteChanged(_ notification: Notification)
    {
        // Unplug headset should pause audio (according to Apple HIG)
        guard let routeChangeRaw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let routeChange = AVAudioSessionRouteChangeReason(rawValue: routeChangeRaw) else {
                NSLog("*** AVAudioSessionRouteChange: no reason argument found")
                return
        }
        NSLog("*** AVAudioSessionRouteChange: \(routeChange)")
        
        if (routeChange != .categoryChange) {
            self.pause()
        }
    }
    
    
    // Configure playback control from the remote control center.
    // Visible when swiping up from the bottom even when other Apps are in the forground,
    // and on the lockscreen while this App is the 'NowPlaying' App.
    // NOTE: There are apparently limit to how many events that can be controlled (3?).
    //       defining any more, will not make them show in the controll center, but they will
    //       still work via f.ex.  the headset remote controll events (if applicable)
    func configureRemoteControlEvents() {
        NSLog("\(#function)...")
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget (handler: { (event) -> MPRemoteCommandHandlerStatus in
            NSLog("playCommand")
            self.play()
            return .success
        })
        commandCenter.pauseCommand.addTarget (handler: { (event) -> MPRemoteCommandHandlerStatus in
            NSLog("pauseCommand")
            self.pause()
            return .success
        })
        // Headset remote sends this signal on single click .....
        commandCenter.togglePlayPauseCommand.addTarget (handler: { (event) -> MPRemoteCommandHandlerStatus in
            NSLog("togglePlayPauseCommand \(event.description)")
            if ( self.isPlaying ) {
                self.pause()
            } else {
                self.play()
            }
            return .success
        })
        
        commandCenter.previousTrackCommand.addTarget (handler: { (event) -> MPRemoteCommandHandlerStatus in
            NSLog("previousTrackCommand \(event.description)")
            self.previousAudioTrack() {}
            return .success
        })
        commandCenter.previousTrackCommand.isEnabled = true
        
        // Can be sent by double-clicking on the headset remote
        commandCenter.nextTrackCommand.addTarget (handler: { (event) -> MPRemoteCommandHandlerStatus in
            NSLog("nextTrackCommand \(event.description)")
            self.nextAudioTrack() {}
            return .success
        })
        commandCenter.nextTrackCommand.isEnabled = true
        
        // Currently unsure what can send this ????
        commandCenter.changePlaybackRateCommand.addTarget (handler: { (event) -> MPRemoteCommandHandlerStatus in
            NSLog("changePlaybackRateCommand \(event.description)")
            return .success
        })
        commandCenter.changePlaybackRateCommand.isEnabled = true
        commandCenter.changePlaybackRateCommand.supportedPlaybackRates = [ 0.5, 1.0, 1.5, 2.0 ]
        
        
        // Not shure what sends this event?
        /*
         commandCenter.seekBackwardCommand.addTargetWithHandler { (event) -> MPRemoteCommandHandlerStatus in
         NSLog("seekBackwardCommand \(event.description)")
         return .Success
         }
         commandCenter.seekBackwardCommand.enabled = true
         
         commandCenter.seekForwardCommand.addTargetWithHandler { (event) -> MPRemoteCommandHandlerStatus in
         NSLog("seekForwardCommand \(event.description)")
         return .Success
         }
         commandCenter.seekForwardCommand.enabled = true
         */
        
        
        // Not room in the command center for both skip forward/backward and previous/next track ?
        /*
         commandCenter.skipBackwardCommand.addTargetWithHandler { (event) -> MPRemoteCommandHandlerStatus in
         NSLog("skipBackwardCommand \(event.description)")
         return .Success
         }
         commandCenter.skipBackwardCommand.enabled = true
         
         commandCenter.skipForwardCommand.addTargetWithHandler { (event) -> MPRemoteCommandHandlerStatus in
         NSLog("skipForwardCommand \(event.description)")
         return .Success
         }
         commandCenter.skipForwardCommand.enabled = true
         */
        
        if #available(iOS 9.1, *) {
            commandCenter.changePlaybackPositionCommand.addTarget (handler: { (event) -> MPRemoteCommandHandlerStatus in
                NSLog("changePlaybackPositionCommand \(event.description)")
                return .success
            })
            commandCenter.changePlaybackPositionCommand.isEnabled = true
        }
        
        // Command center has a build in bookmark function. Do we want to use that? If we enable it, there are apparently not room for previous/next track
        /*
         commandCenter.bookmarkCommand.addTargetWithHandler { (event) -> MPRemoteCommandHandlerStatus in
         NSLog("bookmarkCommand \(event.description)")
         return .Success
         }
         commandCenter.bookmarkCommand.enabled = false
         */
    }
}
