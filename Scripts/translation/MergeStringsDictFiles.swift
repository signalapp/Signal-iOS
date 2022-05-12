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

func hasInvalidPlaceholder(string template: String, placeholder: String, fallback: String?) -> Bool {
    var template = template[...]
    var placeholderAlreadyReferenced = false
    while let index = template.firstIndex(of: "%") {
        template = template[index...].dropFirst()
        // check whether the placeholder is referenced more than once (which isn't allowed)
        if template.starts(with: placeholder) {
            if placeholderAlreadyReferenced {
                return true
            }
            placeholderAlreadyReferenced = true
        } else if let item = template.components(separatedBy: "$").first {
            // we never have more than three arguments passed to NSLocalizedString
            if !["2", "3"].contains(item) {
                return true
            }
            // check whether this placeholder is contained in the fallback (if provided)
            else if let fallback = fallback, !fallback.contains("%\(item)$") {
                return true
            }
        }
    }
    return false
}

func hasInvalidPlaceholder(contents: [String: Any]?, fallback: [String: Any]?) -> Bool {
    guard let contents = contents else {
        return true
    }
    var hasError = false
    for key in contents.keys {
        let fallback = fallback?[key] as? [String: Any]
        if let entry = contents[key] as? [String: Any], let placeholder = entry["NSStringFormatValueTypeKey"] as? String,
          "NSStringPluralRuleType" == entry["NSStringFormatSpecTypeKey"] as? String {
            for variant in ["zero", "one", "two", "few", "many", "other"] {
                if let template = entry[variant] as? String {
                    if hasInvalidPlaceholder(string: template, placeholder: placeholder, fallback: fallback?[variant] as? String) {
                        print("*** template for variant \(variant) with placeholder \(placeholder) is invalid: \(template)")
                        hasError = true
                    }
                }
            }
        }
    }
    return hasError
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
                // if the entry contains invalid usage of placeholders replace it, too 
                else if hasInvalidPlaceholder(contents: destinationDict[key] as? [String: Any],
                  fallback: sourceDict[key] as? [String: Any]) {
                    destinationDict[key] = sourceDict[key]
                    changed = true
                    print("replacing \(key) due to invalid format usage")
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
