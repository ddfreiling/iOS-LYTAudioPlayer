//
//  ViewController.swift
//  AudioQueuePlayerDemo
//
//  Created by Lyt on 10/05/16.
//  Copyright © 2016 Nota. All rights reserved.
//

import UIKit
import AudioToolbox
import AVFoundation
import LYTAudioPlayer

// TODO: Consider alternatives to home-rolled Player
// https://github.com/tumtumtum/StreamingKit
// https://github.com/NoonPacific/NPAudioStream
// https://github.com/delannoyk/AudioPlayer

class ViewController: UIViewController, LYTPlayerDelegate {

    @IBOutlet weak var btnPlay: UIButton!
    @IBOutlet weak var imageView: UIImageView!
    
    var player: LYTPlayer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        //UIApplication.sharedApplication().beginReceivingRemoteControlEvents()
        // Do any additional setup after loading the view, typically from a nib.
        
            }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    // MARK: Actions
    @IBAction func onPlayClicked(_ sender: UIButton) {
        NSLog("Play Clicked")
        let myPlaylist = LYTPlaylist()
        myPlaylist.addTrack(
            LYTAudioTrack(url: URL(string:"https://archive.org/download/George-Orwell-1984-Audio-book/1984-01.mp3")!,
                title: "Skyggeforbandelsen", artist: "Helene Tegtmeier", album: "Del 1 af 3", albumArtUrl: URL(string:"http://bookcover.nota.dk/714070_w140_h200.jpg")))
        myPlaylist.addTrack(
            LYTAudioTrack(url: URL(string:"https://archive.org/download/George-Orwell-1984-Audio-book/1984-02.mp3")!,
                title: "Skyggeforbandelsen", artist: "Helene Tegtmeier", album: "Del 2 af 3", albumArtUrl: URL(string:"http://bookcover.nota.dk/714070_w140_h200.jpg")))
        myPlaylist.addTrack(
            LYTAudioTrack(url: URL(string:"https://archive.org/download/George-Orwell-1984-Audio-book/1984-03.mp3")!,
                title: "Skyggeforbandelsen", artist: "Helene Tegtmeier", album: "Del 3 af 3", albumArtUrl: URL(string:"http://bookcover.nota.dk/714070_w140_h200.jpg")))
        myPlaylist.addTrack(
            LYTAudioTrack(url: URL(string:"https://archive.org/download/George-Orwell-1984-Audio-book/1984-04.mp3")!,
                title: "title", artist: "artist", album: "album", albumArtUrl:
                    URL(string:"http://bookcover.nota.dk/714070_w140_h200.jpg")))
        
        player = LYTPlayer.sharedInstance
        player.delegate = self;
        player.loadPlaylist(myPlaylist, initialPlaylistIndex: 0)
    }
    
    @IBAction func onPauseClicked(_ sender: UIButton) {
        NSLog("Pause Clicked")
        if (player.isPlaying) {
            player.pause()
        } else {
            player.play()
        }
    }
    
    @IBAction func onPreviousClicked(_ sender: UIButton) {
        NSLog("Previous Clicked")
        player.previousAudioTrack() {}
    }
    
    @IBAction func onNextClicked(_ sender: UIButton) {
        NSLog("Next Clicked")
        player.nextAudioTrack() {}
    }
    
    @IBAction func onSeekClicked(_ sender: UIButton) {
        NSLog("Seek Clicked")
        player.skipToPlaylistIndex(3, onCompletion: {
            NSLog("===========> Skip completed")
            self.player.seekToTimeMilis(10000, onCompletion: {
                NSLog("===========> Seek completed");
                self.player.play()
            })
        })
    }
    
    @IBAction func onStopClicked(_ sender: UIButton) {
        NSLog("Stop Clicked")
        player.stop()
    }
    
    @IBAction func onShowImageClicked(_ sender: UIButton) {
        NSLog("ShowImage Clicked")
        if let track = player.currentTrack {
            if let image = track.albumArtCachedImage {
                NSLog("== View received cached image: (width) %f", image.size.width)
                imageView.image = track.albumArtCachedImage
            } else {
                NSLog("== View did not receive any album artwork image")
            }
        }
    }
    
    func didChangeStateFrom(_ from: LYTPlayerState, to: LYTPlayerState) {
        NSLog("Delegate: state-change: \(from.rawValue) -> \(to.rawValue)")
        if (to == .ready) {
            NSLog("ready -> Play!");
            player.play()
        }
    }
    func didFinishPlayingTrack(_ track: LYTAudioTrack) {
        NSLog("Delegate: finish item: \(track.title)")
    }
    func didFindDuration(_ duration: Double, forTrack track: LYTAudioTrack) {
        NSLog("Delegate: duration found for item \(track.title) = \(duration)")
    }
    func didUpdateBufferedDuration(_ buffered: Double, forTrack track: LYTAudioTrack) {
        //NSLog("Delegate: buffered: \(track.title) >> \(buffered)s")
    }
    func didChangeToTrack(_ track: LYTAudioTrack) {
        NSLog("Delegate: changed current track: \(track.title)")
    }
    func didEncounterError(_ error:NSError) {
        NSLog("Delegate: ERROR! \(error.localizedDescription)");
    }
}

