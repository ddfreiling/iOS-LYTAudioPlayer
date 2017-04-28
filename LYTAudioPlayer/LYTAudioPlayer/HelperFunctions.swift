//
//  HelperFunctions.swift
//  AudioQueuePlayer
//
//  Misc generic helper functions for the LytPlayer
//
//  Created by Bo Frese on 19/2-16.
//  Copyright © 2016 Nota.dk. All rights reserved.
//

import Foundation
import UIKit

// Convenience types and functions .......

// -------------------------------------------------------------------------------------
// MARK: - Async utilities

private let bgSerialQueue = DispatchQueue(label: "serial-worker", attributes: [])
/// Run a function/closeure on a backround serial queue.
func onSerialQueue( _ closure: @escaping () -> () ) {
    bgSerialQueue.async {
        closure()
    }
}
/// Run a function/closeure on the main (UI) queue. If we are already on the main thread then just run the function/closure.
func onMainQueue( _ closure: @escaping () -> () ) {
    if (Thread.isMainThread) {
        closure()
    } else {
        DispatchQueue.main.async {
            closure()
        }
    }
}

// -------------------------------------------------------------------------------------
// MARK: - Filesystem and URL utilities

func fileURL(_ filename: String) -> URL {
    // let fileURL = documentsURL().URLByAppendingPathComponent(filename)
    // TODO: Currently we only llok for resoruces, and not file in the Documents directory....
    let fileURL = resourceURL().appendingPathComponent(filename)
    return fileURL
}

func fileExists(_ filename: String) -> Bool {
    let url = fileURL(filename)
    let path = url.path
    let exists = FileManager.default.fileExists(atPath: path)
    return exists
}

func readFile(_ filename: String) throws -> String {
    let contentString = try String(contentsOf: fileURL(filename), encoding: String.Encoding.utf8)
    return contentString
}

func documentsURL() -> URL {
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    return documentsURL
}

func resourceURL() -> URL {
    return URL(fileURLWithPath: resourcePath())
}

func resourcePath() -> String {
    let path = Bundle.main.resourcePath!
    return path
}

func debugDumpDir(_ dir: String) {
    NSLog("Dump \(dir)")
    let files = try! FileManager.default.contentsOfDirectory(atPath: dir)
    NSLog("- files : \(files)")
}

// MARK: - Regular Expressions
//-----------------------------------------------------------------------------------------
// SwiftRegex.swift
// https://github.com/kasei/SwiftRegex/blob/master/SwiftRegex/SwiftRegex.swift
//
//  Created by Gregory Todd Williams on 6/7/14.
//  Copyright (c) 2014 Gregory Todd Williams. All rights reserved.
//


infix operator =~

func =~ (value : String, pattern : String) -> RegexMatchResult {
    let nsstr = value as NSString // we use this to access the NSString methods like .length and .substringWithRange(NSRange)
    let options : NSRegularExpression.Options = []
    do {
        let re = try  NSRegularExpression(pattern: pattern, options: options)
        let all = NSRange(location: 0, length: nsstr.length)
        var matches : Array<String> = []
        re.enumerateMatches(in: value, options: [], range: all) { (result, flags, ptr) -> Void in
            guard let result = result else { return }
            let string = nsstr.substring(with: result.range)
            matches.append(string)
        }
        return RegexMatchResult(items: matches)
    } catch {
        return RegexMatchResult(items: [])
    }
}

struct RegexMatchCaptureGenerator : IteratorProtocol {
    var items: ArraySlice<String>
    mutating func next() -> String? {
        if items.isEmpty { return nil }
        let ret = items[items.startIndex]
        items = items[1..<items.count]
        return ret
    }
}

struct RegexMatchResult : Sequence {
    var items: Array<String>
    func makeIterator() -> RegexMatchCaptureGenerator {
        return RegexMatchCaptureGenerator(items: items[0..<items.count])
    }
    var boolValue: Bool {
        return items.count > 0
    }
    subscript (i: Int) -> String {
        return items[i]
    }
}
