#!/usr/bin/env xcrun swift

import Foundation

// The way this works is:
// • Run the AbandonedStrings executable (see https://www.avanderlee.com/xcode/unused-localized-strings/)
// • Paste the list of unused strings below
// • Run this script by doing:
//   swiftc remove_unused_strings.swift
//   ./remove_unused_strings

let unusedStringKeys = [
    
]

let allFileURLs = try! FileManager.default.contentsOfDirectory(at: URL(string: "./")!, includingPropertiesForKeys: nil)
let translationFiles = allFileURLs.map { $0.lastPathComponent }.filter { $0.hasSuffix(".lproj") }

for translationFile in translationFiles {
    let contents = try! String(contentsOfFile: "\(translationFile)/Localizable.strings")
    let lines = contents.split(separator: "\n")
    var filteredLines0: [String] = []
    for line in lines {
        if !unusedStringKeys.contains(where: { line.hasPrefix("\"\($0)\"") }) {
            filteredLines0.append(String(line))
        }
    }
    var filteredLines1: [String] = []
    for (index, line) in filteredLines0.enumerated() {
        if line.hasPrefix("/*") && index != (filteredLines0.count - 1) && filteredLines0[index + 1].hasPrefix("/*") {
            // Orphaned comment; drop it
        } else {
            filteredLines1.append(line)
        }
    }
    let newContents = filteredLines1.joined(separator: "\n")
    try newContents.write(to: URL(fileURLWithPath: "\(FileManager.default.currentDirectoryPath)/\(translationFile)/Localizable.strings"), atomically: true, encoding: String.Encoding.utf8)
}
