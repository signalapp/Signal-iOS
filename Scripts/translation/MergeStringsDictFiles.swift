//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

func readPlistFile(path: String) -> [String: Any]? {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
    } catch {
    }
    return nil
}

func writePlistFile(contents: [String: Any], path: String) -> Bool {
    do {
        let data = try PropertyListSerialization.data(fromPropertyList: contents, format: .xml, options: 0)
        try? data.write(to: URL(fileURLWithPath: path))
        return true
    } catch {
    }
    return false
}

if CommandLine.arguments.count != 3 {
    print("usage MergeStringsDictFiles <defaultLanguageFile> <targetLanguageFile>")
} else {
    let sourcePath = CommandLine.arguments[1]
    let destinationPath = CommandLine.arguments[2]
    if let destinationDict = readPlistFile(path: destinationPath) {
        var destinationDict = destinationDict
        if let sourceDict = readPlistFile(path: sourcePath) {
            var changed = false
            for key in sourceDict.keys {
                // if the entry is completely missing take it from the source
                if !destinationDict.keys.contains(key) {
                    destinationDict[key] = sourceDict[key]
                    changed = true
                    print("added \(key)")
                }
                // if the entry only contains the format key replace it, too
                else if let entries = destinationDict[key] as? [String: Any], entries.keys.count < 2 {
                    destinationDict[key] = sourceDict[key]
                    changed = true
                    print("updated \(key)")
                }
            }
            if changed {
                if writePlistFile(contents: destinationDict, path: destinationPath) {
                    print("\(destinationPath) updated")
                } else {
                    print("error updating \(destinationPath)")
                }
            }
        } else {
            print("skipped \(destinationPath), because source file \(sourcePath) does not exist or doesn't contain valid entries")
        }
    } else {
        print("skipped \(destinationPath), does not exist or doesn't contain valid entries")
    }
}
