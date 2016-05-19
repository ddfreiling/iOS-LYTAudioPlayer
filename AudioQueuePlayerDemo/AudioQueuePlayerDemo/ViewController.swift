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
import AudioQueuePlayer

// TODO: Consider alternatives to home-rolled Player
// https://github.com/tumtumtum/StreamingKit
// https://github.com/NoonPacific/NPAudioStream
// https://github.com/delannoyk/AudioPlayer

class ViewController: UIViewController {

    @IBOutlet weak var btnPlay: UIButton!
    @IBOutlet weak var imageView: UIImageView!
    
    var player: LYTPlayer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        //UIApplication.sharedApplication().beginReceivingRemoteControlEvents()
        // Do any additional setup after loading the view, typically from a nib.
        
        let myPlaylist = LYTPlaylist()
        myPlaylist.addTrack(
            LYTAudioTrack(url: NSURL(string:"http://www.noiseaddicts.com/samples_1w72b820/3714.mp3")!,
                title: "Intro Sound", artist: "Artist", album: "Intro", albumArtUrl: NSURL(string:"http://bookcover.nota.dk/714070_w140_h200.jpg")))
        myPlaylist.addTrack(
            LYTAudioTrack(url: NSURL(string:"https://archive.org/download/George-Orwell-1984-Audio-book/1984-01.mp3")!,
                title: "Skyggeforbandelsen", artist: "Helene Tegtmeier", album: "Del 1 af 3", albumArtUrl: NSURL(string:"http://bookcover.nota.dk/714070_w140_h200.jpg")))
        myPlaylist.addTrack(
            LYTAudioTrack(url: NSURL(string:"https://archive.org/download/George-Orwell-1984-Audio-book/1984-02.mp3")!,
                title: "Skyggeforbandelsen", artist: "Helene Tegtmeier", album: "Del 2 af 3", albumArtUrl: NSURL(string:"http://bookcover.nota.dk/714070_w140_h200.jpg")))
        myPlaylist.addTrack(
            LYTAudioTrack(url: NSURL(string:"https://archive.org/download/George-Orwell-1984-Audio-book/1984-03.mp3")!,
                title: "Skyggeforbandelsen", artist: "Helene Tegtmeier", album: "Del 3 af 3", albumArtUrl: NSURL(string:"http://bookcover.nota.dk/714070_w140_h200.jpg")))
        myPlaylist.addTrack(
            LYTAudioTrack(url: NSURL(string:"https://archive.org/download/George-Orwell-1984-Audio-book/1984-04.mp3")!,
                title: "title", artist: "artist", album: "album", albumArtUrl: NSURL(string:"http://bookcover.nota.dk/714070_w140_h200.jpg")))
        
        
        player = LYTPlayer.sharedInstance
        player.loadPlaylist(myPlaylist)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    // MARK: Actions
    @IBAction func onPlayClicked(sender: UIButton) {
        NSLog("Play Clicked")
        player.play()
    }
    
    @IBAction func onPauseClicked(sender: UIButton) {
        NSLog("Pause Clicked")
        player.pause()
    }
    
    @IBAction func onPreviousClicked(sender: UIButton) {
        NSLog("Previous Clicked")
        player.previousAudioTrack()
    }
    
    @IBAction func onNextClicked(sender: UIButton) {
        NSLog("Next Clicked")
        player.nextAudioTrack()
    }
    
    @IBAction func onSeekClicked(sender: UIButton) {
        NSLog("Seek Clicked")
        let time: Int = player.currentTime()
        NSLog("CurrentTime: \(time)")
        player.seekTo(10000, playlistIndex: 0)
    }
    
    @IBAction func onStopClicked(sender: UIButton) {
        NSLog("Stop Clicked")
        player.stop()
    }
    
    @IBAction func onShowImageClicked(sender: UIButton) {
        NSLog("ShowImage Clicked")
        if let track = player.currentTrack() {
            if let image = track.albumArtCachedImage {
                NSLog("== View received cached image: (width) %f", image.size.width)
                imageView.image = track.albumArtCachedImage
            } else {
                NSLog("== View did not receive any album artwork image")
            }
        }
    }
}

