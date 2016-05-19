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

public enum AudioQueuePlayerState {
    case Buffering
    case Playing
    case Paused
    case Stopped
    case WaitingForConnection
    case Failed
}
extension AudioQueuePlayerState: Equatable { }

public protocol LYTPlayerDelegate: NSObjectProtocol {
    func audioPlayer(audioPlayer: LYTPlayer, didChangeStateFrom from: AudioQueuePlayerState, toState to: AudioQueuePlayerState)
    func audioPlayer(audioPlayer: LYTPlayer, didFinishPlayingItem item: AudioTrack)
    func audioPlayer(audioPlayer: LYTPlayer, didFindDuration duration: Double, forTrack track: AudioTrack)
    func audioPlayer(audioPlayer: LYTPlayer, didUpdateBuffering buffered: Double, forTrack track: AudioTrack)
    func audioPlayer(audioPlayer: LYTPlayer, didBeginPlaybackForTrack track: AudioTrack)
    func audioPlayer(audioPlayer: LYTPlayer, didFinishSeekingToTime time: CMTime)
    func audioPlayer(audioPlayer: LYTPlayer, didEncounterError error:NSError)
}

@objc public class LYTPlayer : NSObject {
    
    var audioPlayer = AVQueuePlayer()
    var authorizationFailedCallback: Callback?
    var currentPlaylist: Playlist?
    var currentPlaylistIndex: Int = 0
    
    let observerManager = ObserverManager() // For KVO - see: https://github.com/timbodeit/ObserverManager
    
    public weak var delegate: LYTPlayerDelegate?
    
    public static let sharedInstance = LYTPlayer()
    
    private override init() {
        super.init()
        state = AudioQueuePlayerState.Stopped
        audioPlayer.actionAtItemEnd = .Advance
        configureRemoteControlEvents()
    }
    
    deinit {
        stop()
    }
    
    // MARK: Readonly properties
    
    /// The current state of the player.
    public private(set) var state = AudioQueuePlayerState.Stopped {
        didSet {
            if state != oldValue || state == .WaitingForConnection {
                delegate?.audioPlayer(self, didChangeStateFrom: oldValue, toState: state)
            }
        }
    }
    
    // MARK: Public API
    
    public func loadPlaylist(playlist: Playlist) {
        currentPlaylist = playlist
        currentPlaylistIndex = 0;
        setupCurrentAudioPart(currentPlaylistIndex, success: { NSLog("setup success") })
    }
    
    public func play() {
        guard let _ = currentPlaylist else { NSLog("NO currentPlaylist in \(#function)"); return }
        NSLog("\(#function)...")
        
        // Verify that we are ready to play....
        if ( audioPlayer.status == .ReadyToPlay ) {
            NSLog("LYTPlayer is READY")
            if let status = audioPlayer.currentItem?.status {
                switch status  {
                case AVPlayerItemStatus.ReadyToPlay :
                    NSLog("CurrentItem is READY")
                case AVPlayerItemStatus.Failed :
                    NSLog("CurrentItem FAILED")
                default :
                    NSLog("CurrentItem is in an unknown state...")
                }
            } else {
                NSLog("LYTPlayer currentItem is in trouble: \(audioPlayer.currentItem.debugDescription)")
            }
        } else {
            NSLog("*** LYTPlayer is NOT READY : \(audioPlayer.error?.localizedDescription) ***")
        }
        
        pausedByAudioSessionInterrupt = false
        setupAudioActive(true)
        audioPlayer.play()
        NSLog("LYTPlayer.play() status: \(currentStatus() )")
        state = AudioQueuePlayerState.Playing
    }
    
    func currentStatus() -> String {
        guard let currentPlaylist = currentPlaylist else { NSLog("NO currentPlaylist in \(#function)"); return "No current playlist" }
        let track = currentPlaylist.tracks[currentPlaylistIndex]
        let status = "'\(track.title)' (\(currentPlaylistIndex)/\(currentPlaylist.tracks.count)) \(track.url)"
        return status
    }
    
    public func pause() {
        NSLog("\(#function)...")
        audioPlayer.pause()
        // TODO: Register where we are so can continue where we stopped.
        setupAudioActive(false)
        state = AudioQueuePlayerState.Paused
    }
    
    public func stop() {
        NSLog("\(#function)...")
        audioPlayer.pause() // AVPlayer does not have a stop method
        self.observerManager.deregisterAllObservers()
        self.audioPlayer.removeAllItems()
        state = AudioQueuePlayerState.Stopped
    }
    
    public func isPlaying() -> Bool
    {
        return (audioPlayer.rate > 0.0);
    }
    
    public func nextAudioTrack() {
        guard let currentPlaylist = currentPlaylist else { NSLog("NO currentPlaylist in \(#function)"); return }
        if ( currentPlaylistIndex + 1 < currentPlaylist.trackCount ) {
            stop()
            setupCurrentAudioPart( currentPlaylistIndex + 1) { self.play() }
        } else {
            stop()
        }
    }
    
    public func previousAudioTrack() {
        setupCurrentAudioPart( max(currentPlaylistIndex - 1, 0) ) { self.play() }
    }
    
    public func currentTime() -> Int {
        return lround(audioPlayer.currentTime().seconds * 1000)
    }
    
    public func seekTo(time: Int, playlistIndex: Int?) {
        let newTime: CMTime = CMTimeMake(Int64(time), 1000)
        audioPlayer.seekToTime(newTime, completionHandler: { _ in
            self.delegate?.audioPlayer(self, didFinishSeekingToTime: newTime)
        })
    }
    
    public func currentTrack() -> AudioTrack? {
        return currentPlaylist?.tracks[currentPlaylistIndex]
    }
    
    // Return true if succesful.
    func setupAudioActive(active: Bool) -> Bool {
        NSLog("\(#function)( \(active) )...")
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(AVAudioSessionCategoryPlayback)
            try audioSession.setActive(active, withOptions: .NotifyOthersOnDeactivation ) // ??? Options
            
            NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(LYTPlayer.audioSessionInterrupted), name: AVAudioSessionInterruptionNotification, object: audioSession)
            
            NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(LYTPlayer.audioSessionRouteChanged), name: AVAudioSessionRouteChangeNotification, object: audioSession)
            return true
        } catch {
            NSLog("Error setting AudioSession !!!!!!!!!")
            // TODO: More error handling?
            return false
        }
    }
    
    func resetPlayer() {
        NSNotificationCenter.defaultCenter().removeObserver(self)
        audioPlayer.pause()
        audioPlayer.removeAllItems()
        setupAudioActive(false)
    }
    
    func setupCurrentAudioPart(playlistIndex: Int = 0, success: () -> () = {} ) {
        guard let _ = currentPlaylist else { NSLog("NO currentPlaylist in \(#function)"); return }
        NSLog("setupCurrentAudioPart( \(playlistIndex)) ...")
        self.stop()
        self.setupAudioPlayerObservers()
        NSLog("setupCurrentAudioPart() - audioPlayer Initialized ...")
        self.currentPlaylistIndex = playlistIndex
        addItemToPlayerQueue(self.currentPlaylistIndex)
        success()
    }
    
    /// Added a player item for a given part to the play queue, and setup observers to automatically schedule the following parts.
    func addItemToPlayerQueue( playlistIndex: Int ) {
        guard let currentPlaylist = currentPlaylist else { NSLog("NO currentPlaylist in \(#function)"); return }
        let track = currentPlaylist.tracks[playlistIndex]
        NSLog("Add to Queue: \(track.url.lastPathComponent) from URL: \(track.url)")
        let asset = AVURLAsset(URL: track.url)
        let item = AVPlayerItem.init(asset: asset, automaticallyLoadedAssetKeys: ["duration","playable","tracks"]) // Asset keys that need to be present before the item is 'ready'
        self.setupPlayerItemObservers(item, itemPlaylistIndex: playlistIndex)
        self.audioPlayer.insertItem(item, afterItem: nil) // append item to player queue
    }
    
    func setupPlayerItemObservers(item: AVPlayerItem, itemPlaylistIndex: Int) {
        NSNotificationCenter.defaultCenter()
            .addObserver(self, selector: #selector(finishedPlayingItem), name: AVPlayerItemDidPlayToEndTimeNotification, object: item)
        let itemTrack: AudioTrack = self.currentPlaylist!.tracks[itemPlaylistIndex]
        item.whenChanging("status", manager: observerManager ) { item in
            switch item.status {
            case .Failed:
                NSLog("--> PlayerItem FAILED: \(item.asset.debugDescription)")
            case .ReadyToPlay:
                NSLog("--> PlayerItem READY: \(item.asset.debugDescription)")
                let nextPlaylistIndex = itemPlaylistIndex + 1
                if (nextPlaylistIndex < self.currentPlaylist?.trackCount) {
                    self.addItemToPlayerQueue(nextPlaylistIndex)
                }
                self.delegate?.audioPlayer(self, didFindDuration: item.duration.seconds, forTrack: itemTrack)
            case .Unknown :
                NSLog("--> PlayerItem UNKNOWN status: \(item.asset.debugDescription)")
            }
            
            if let error = item.error {
                NSLog("--- Item Error: \(error.localizedDescription) reason: \(error.localizedFailureReason) - UserInfo: \(error.userInfo.debugDescription)")
                if ( error.code == NSURLErrorUserAuthenticationRequired ) { // Error codes: http://nshipster.com/nserror/
                    NSLog("*** Authentication Required !!!! ***")
                    // TODO: Callback to UI ? Deal with Authentication .....
                    // TODO: Remember where we where. Check if something is playing? (then what??)
                    self.pause() // TODO: Can we just resume when we come back???
                    self.authorizationFailedCallback?()
                } else {
                    NSLog("*** UNHANDLED ERROR !!!! ***")
                    // TODO: Deal with other item errors .......
                    self.delegate?.audioPlayer(self, didEncounterError: error)
                }
            }
        }
        item.whenChanging("loadedTimeRanges", manager: observerManager) { item in
            let durationLoaded = self.durationLoadedOfItem(item)
            NSLog("___loadedTimeRanges changed: \(durationLoaded)")
            self.delegate?.audioPlayer(self, didUpdateBuffering: durationLoaded, forTrack: itemTrack)
        }
    }
    
    func durationLoadedOfItem(item: AVPlayerItem) -> Double {
        NSLog("-> Item has \(item.loadedTimeRanges.count) time ranges");
        let timeRange: CMTimeRange = item.loadedTimeRanges[0].CMTimeRangeValue
        let loadedDuration: Double = CMTimeGetSeconds(timeRange.duration)
        return loadedDuration
    }
    
    func finishedPlayingItem() {
        // LYTPlayer finished playing track and will automatically start playing the next
        // Notify delegate and update the index of currently played track
        if let currentTrack = self.currentPlaylist?.tracks[currentPlaylistIndex] {
            self.delegate?.audioPlayer(self, didFinishPlayingItem: currentTrack)
        }
        self.currentPlaylistIndex += 1
    }
    
    // Now playing info is showed on the lock screen and the control center.
    func updateNowPlayingInfo() {
        guard let currentPlaylist = currentPlaylist else { NSLog("NO currentPlaylist in \(#function)"); return }
        NSLog("\(#function)...")
        let currentTrack: AudioTrack = currentPlaylist.tracks[currentPlaylistIndex]
        
        NSLog("Updating NowPlayingInfo for: \(currentTrack.title)")
        let infoCenter = MPNowPlayingInfoCenter.defaultCenter()
        var info = [String: AnyObject]()
        info[MPMediaItemPropertyMediaType] = MPMediaType.AudioBook.rawValue // Not sure we need this, or what it does....
        info[MPMediaItemPropertyAlbumArtist] = currentTrack.artist
        info[MPMediaItemPropertyAlbumTitle] = currentTrack.album
        info[MPMediaItemPropertyTitle] = currentTrack.title
        info[MPNowPlayingInfoPropertyChapterNumber] = self.currentPlaylistIndex + 1
        info[MPNowPlayingInfoPropertyChapterCount] = currentPlaylist.trackCount
        info[MPMediaItemPropertyAlbumTrackNumber] = self.currentPlaylistIndex + 1
        info[MPNowPlayingInfoPropertyPlaybackRate] = self.audioPlayer.rate
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = self.audioPlayer.currentItem?.currentTime().seconds
        info[MPMediaItemPropertyPlaybackDuration] = self.audioPlayer.currentItem?.duration.seconds
        if let artImage = currentTrack.albumArtCachedImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(image: artImage)
        }
        infoCenter.nowPlayingInfo = info
        
        // Set artwork image async
        guard let imageUrl = currentTrack.albumArtUrl where currentTrack.albumArtCachedImage == nil else {
            NSLog("==> No album artwork url specified or already cached")
            return
        }
        onSerialQueue({
            guard let artworkImageData = NSData(contentsOfURL: imageUrl),
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
            })
            NSLog("=== ARTWORK IMAGE SET ===")
        })
    }
    
    func getArtworkImageFromUrl(imageUrlPath: String) -> UIImage? {
        guard let imageUrl = NSURL(string: imageUrlPath),
            let artworkImageData = NSData(contentsOfURL: imageUrl),
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
            NSLog("==> AudioPlayer new current item \(player.currentItem?.asset.debugDescription)")
            self.updateNowPlayingInfo()
        }
        audioPlayer.whenChanging("status", manager: observerManager) { player in
            switch( player.status) {
            case .Failed :
                NSLog("*** LYTPlayer Failed!")
            case .ReadyToPlay :
                NSLog("+++ LYTPlayer is ready to play!")
            case .Unknown :
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
    
    private var pausedByAudioSessionInterrupt = false
    
    // Called whenever we get interrupted (by f.ex. phone call, Alarm clock, etc.)
    func audioSessionInterrupted(notification: NSNotification)
    {
        guard let interruptTypeRaw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let interruptType = AVAudioSessionInterruptionType(rawValue: interruptTypeRaw) else {
                NSLog("*** AVAudioSessionInterruption: no type argument found")
                return
        }
        NSLog("*** AVAudioSessionInterruption: \(interruptType)")
        
        switch interruptType {
        case .Began:
            pausedByAudioSessionInterrupt = true
            self.pause()
            break
        case .Ended:
            if (!self.isPlaying() && pausedByAudioSessionInterrupt) {
                self.play()
                pausedByAudioSessionInterrupt = false
            }
            break
        }
    }
    
    // Called whenever we the audio route is changed (f.ex. switch to headset og AirPlay)
    // https://developer.apple.com/library/ios/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/HandlingAudioHardwareRouteChanges/HandlingAudioHardwareRouteChanges.html#//apple_ref/doc/uid/TP40007875-CH5-SW1
    func audioSessionRouteChanged(notification: NSNotification)
    {
        // Unplug headset should pause audio (according to Apple HIG)
        guard let routeChangeRaw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let routeChange = AVAudioSessionRouteChangeReason(rawValue: routeChangeRaw) else {
                NSLog("*** AVAudioSessionInterruption: no type argument found")
                return
        }
        NSLog("*** AVAudioSessionRouteChange: \(routeChange)")
        
        if (routeChange != .CategoryChange) {
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
        let commandCenter = MPRemoteCommandCenter.sharedCommandCenter()
        commandCenter.playCommand.addTargetWithHandler { (event) -> MPRemoteCommandHandlerStatus in
            NSLog("playCommand")
            self.play()
            return .Success
        }
        commandCenter.pauseCommand.addTargetWithHandler { (event) -> MPRemoteCommandHandlerStatus in
            NSLog("pauseCommand")
            self.pause()
            return .Success
        }
        // Headset remote sends this signal on single click .....
        commandCenter.togglePlayPauseCommand.addTargetWithHandler { (event) -> MPRemoteCommandHandlerStatus in
            NSLog("togglePlayPauseCommand \(event.description)")
            if ( self.isPlaying() ) {
                self.pause()
            } else {
                self.play()
            }
            return .Success
        }
        
        commandCenter.previousTrackCommand.addTargetWithHandler { (event) -> MPRemoteCommandHandlerStatus in
            NSLog("previousTrackCommand \(event.description)")
            self.previousAudioTrack()
            return .Success
        }
        commandCenter.previousTrackCommand.enabled = true
        
        // Can be sent by double-clicking on the headset remote
        commandCenter.nextTrackCommand.addTargetWithHandler { (event) -> MPRemoteCommandHandlerStatus in
            NSLog("nextTrackCommand \(event.description)")
            self.nextAudioTrack()
            return .Success
        }
        commandCenter.nextTrackCommand.enabled = true
        
        // Currently unsure what can send this ????
        commandCenter.changePlaybackRateCommand.addTargetWithHandler { (event) -> MPRemoteCommandHandlerStatus in
            NSLog("changePlaybackRateCommand \(event.description)")
            return .Success
        }
        commandCenter.changePlaybackRateCommand.enabled = true
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
        
        // Not shure what sends this event?
        commandCenter.changePlaybackPositionCommand.addTargetWithHandler { (event) -> MPRemoteCommandHandlerStatus in
            NSLog("changePlaybackPositionCommand \(event.description)")
            return .Success
        }
        commandCenter.changePlaybackPositionCommand.enabled = true
        
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