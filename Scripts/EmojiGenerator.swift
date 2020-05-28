#!/usr/bin/env xcrun --sdk macosx swift

import Foundation

class EmojiGenerator {
    // from http://stackoverflow.com/a/31480534/255489
    static var pathToFolderContainingThisScript: URL? = {
        let cwd = FileManager.default.currentDirectoryPath

        let script = CommandLine.arguments[0]

        if script.hasPrefix("/") { // absolute
            let path = (script as NSString).deletingLastPathComponent
            return URL(fileURLWithPath: path)
        } else { // relative
            let urlCwd = URL(fileURLWithPath: cwd)

            if let urlPath = URL(string: script, relativeTo: urlCwd) {
                let path = (urlPath.path as NSString).deletingLastPathComponent
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }()

    static let emojiDirectory = URL(fileURLWithPath: "../Signal/src/util/Emoji", isDirectory: true, relativeTo: pathToFolderContainingThisScript!)

    enum EmojiCategory: String, Codable {
        case smileys = "Smileys & Emotion"
        case people = "People & Body"

        // This category is not provided in the data set, but is actually
        // a merger of the categories of `smileys` and `people`
        case smileysAndPeople = "Smileys & People"

        case animals = "Animals & Nature"
        case food = "Food & Drink"
        case activities = "Activities"
        case travel = "Travel & Places"
        case objects = "Objects"
        case symbols = "Symbols"
        case flags = "Flags"
        case skinTones = "Skin Tones"
    }

    static let outputCategories: [EmojiCategory] = [
        .smileysAndPeople,
        .animals,
        .food,
        .activities,
        .travel,
        .objects,
        .symbols,
        .flags
    ]

    struct EmojiData: Codable {
        let name: String?
        let shortName: String
        let unified: String
        let sortOrder: UInt
        let category: EmojiCategory

        var enumName: String {
            // some names don't play nice with swift, so we special case them
            switch shortName {
            case "+1": return "plusOne"
            case "-1": return "negativeOne"
            case "8ball": return "eightBall"
            case "repeat": return "`repeat`"
            case "100": return "oneHundred"
            case "1234": return "oneTwoThreeFour"
            default:
                let uppperCamelCase = shortName.replacingOccurrences(of: "-", with: "_").components(separatedBy: "_").map(titlecase).joined(separator: "")
                return String(uppperCamelCase.unicodeScalars.first!).lowercased() + String(uppperCamelCase.unicodeScalars.dropFirst())
            }
        }

        var emoji: String {
            let unicodeComponents = unified.components(separatedBy: "-").map { Int($0, radix: 16)! }
            return unicodeComponents.map { String(UnicodeScalar($0)!) }.joined()
        }

        func titlecase(_ value: String) -> String {
            guard let first = value.unicodeScalars.first else { return value }
            return String(first).uppercased() + String(value.unicodeScalars.dropFirst())
        }
    }

    static func generate() {
        guard let jsonData = try? Data(contentsOf: URL(string: "https://unicodey.com/emoji-data/emoji.json")!) else {
            fatalError("Failed to download emoji-data json")
        }

        let jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase

        let sortedEmojiData = try! jsonDecoder.decode([EmojiData].self, from: jsonData)
            .sorted { $0.sortOrder < $1.sortOrder }
            .filter { $0.category != .skinTones } // for now, we don't care about skin tones

        // Main enum
        writeBlock(fileName: "Emoji.swift") { fileHandle in
            fileHandle.writeLine("/// A sorted representation of all available emoji")
            fileHandle.writeLine("enum Emoji: String, CaseIterable {")

            for emojiData in sortedEmojiData {
                fileHandle.writeLine("    case \(emojiData.enumName) = \"\(emojiData.emoji)\"")
            }

            fileHandle.writeLine("}")
        }

        // Category lookup
        writeBlock(fileName: "Emoji+Category.swift") { fileHandle in
            // Start Extension
            fileHandle.writeLine("extension Emoji {")

            // Start Category enum
            fileHandle.writeLine("    enum Category: String, CaseIterable {")
            for category in outputCategories {
                fileHandle.writeLine("        case \(category) = \"\(category.rawValue)\"")
            }

            fileHandle.writeLine("")

            // Localized name for category
            fileHandle.writeLine("        var localizedName: String {")
            fileHandle.writeLine("            switch self {")

            for category in outputCategories {
                fileHandle.writeLine("            case .\(category):")
                fileHandle.writeLine("                return NSLocalizedString(\"EMOJI_CATEGORY_\("\(category)".uppercased())_NAME\",")
                fileHandle.writeLine("                                         comment: \"The name for the emoji category '\(category.rawValue)'\")")
            }

            fileHandle.writeLine("            }")
            fileHandle.writeLine("        }")
            fileHandle.writeLine("")

            // Emoji lookup per category
            fileHandle.writeLine("        var emoji: [Emoji] {")
            fileHandle.writeLine("            switch self {")

            let emojiPerCategory = sortedEmojiData.reduce(into: [EmojiCategory: [EmojiData]]()) { result, emojiData in
                var categoryList = result[emojiData.category] ?? []
                categoryList.append(emojiData)
                result[emojiData.category] = categoryList
            }

            for category in outputCategories {
                let emoji: [EmojiData] = {
                    switch category {
                    case .smileysAndPeople:
                        // Merge smileys & people. It's important we initially bucket these seperately,
                        // because we want the emojis to be sorted smileys followed by people
                        return emojiPerCategory[.smileys]! + emojiPerCategory[.people]!
                    default:
                        return emojiPerCategory[category]!
                    }
                }()

                fileHandle.writeLine("            case .\(category):")

                fileHandle.writeLine("                return [")

                emoji.compactMap { $0.enumName }.forEach { name in
                    fileHandle.writeLine("                    .\(name),")
                }

                fileHandle.writeLine("                ]")
            }

            fileHandle.writeLine("            }")
            fileHandle.writeLine("        }")

            // End Category Enum
            fileHandle.writeLine("    }")

            fileHandle.writeLine("")

            // Category lookup per emoji
            fileHandle.writeLine("    var category: Category {")
            fileHandle.writeLine("        switch self {")

            for emojiData in sortedEmojiData {
                let category = [.smileys, .people].contains(emojiData.category) ? .smileysAndPeople : emojiData.category
                fileHandle.writeLine("        case .\(emojiData.enumName): return .\(category)")
            }

            // Write a default case, because this enum is too long for the compiler to validate it's exhaustive
            fileHandle.writeLine("        default: fatalError(\"Unexpected case \\(self)\")")

            fileHandle.writeLine("        }")
            fileHandle.writeLine("    }")

            // End Extension
            fileHandle.writeLine("}")
        }

        // Name lookup
        writeBlock(fileName: "Emoji+Name.swift") { fileHandle in
            // Start Extension
            fileHandle.writeLine("extension Emoji {")

            // Value lookup per emoji
            fileHandle.writeLine("    var name: String? {")
            fileHandle.writeLine("        switch self {")

            for emojiData in sortedEmojiData {
                guard let name = emojiData.name else { continue }
                fileHandle.writeLine("        case .\(emojiData.enumName): return \"\(name)\"")
            }

            fileHandle.writeLine("        default: return nil")

            fileHandle.writeLine("        }")
            fileHandle.writeLine("    }")

            // End Extension
            fileHandle.writeLine("}")
        }
    }

    static func writeBlock(fileName: String, block: (FileHandle) -> Void) {
        if !FileManager.default.fileExists(atPath: emojiDirectory.path) {
            try! FileManager.default.createDirectory(at: emojiDirectory, withIntermediateDirectories: true, attributes: nil)
        }

        let url = URL(fileURLWithPath: fileName, relativeTo: emojiDirectory)

        if FileManager.default.fileExists(atPath: url.path) {
            try! FileManager.default.removeItem(at: url)
        }
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)

        let fileHandle = try! FileHandle(forWritingTo: url)
        defer { fileHandle.closeFile() }

        fileHandle.writeLine("//")
        fileHandle.writeLine("//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.")
        fileHandle.writeLine("//")

        fileHandle.writeLine("")
        fileHandle.writeLine("// This file is generated by EmojiGenerator.swift, do not manually edit it.")
        fileHandle.writeLine("")

        block(fileHandle)
    }
}

extension FileHandle {
    func writeLine(_ string: String) {
        write((string + "\n").data(using: .utf8)!)
    }
}

do {
    EmojiGenerator.generate()
}
