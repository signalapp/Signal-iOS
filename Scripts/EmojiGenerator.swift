//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

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

    enum EmojiCategory: String, Codable, Equatable {
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

    enum SkinTone: String, CaseIterable, Equatable {
        case light = "1F3FB"
        case mediumLight = "1F3FC"
        case medium = "1F3FD"
        case mediumDark = "1F3FE"
        case dark = "1F3FF"

        var sortId: Int { return SkinTone.allCases.firstIndex(of: self)! }

        var unicodeScalar: UnicodeScalar { UnicodeScalar(Int(rawValue, radix: 16)!)! }
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

    struct SkinVariation: Codable {
        let unified: String

        var emoji: String {
            let unicodeComponents = unified.components(separatedBy: "-").map { Int($0, radix: 16)! }
            return unicodeComponents.map { String(UnicodeScalar($0)!) }.joined()
        }
    }

    struct EmojiData: Codable {
        let name: String?
        let shortName: String
        let unified: String
        let sortOrder: UInt
        let category: EmojiCategory
        let skinVariations: [String: SkinVariation]?

        var enumName: String {
            // some names don't play nice with swift, so we special case them
            switch shortName {
            case "+1": return "plusOne"
            case "-1": return "negativeOne"
            case "8ball": return "eightBall"
            case "repeat": return "`repeat`"
            case "100": return "oneHundred"
            case "1234": return "oneTwoThreeFour"
            case "couplekiss": return "personKissPerson"
            case "couple": return "womanAndManHoldingHands"
            case "couple_with_heart": return "personHeartPerson"
            case "beetle":
                if name == "LADY BEETLE" { return "ladyBeetle" }
                return "beetle"
            case "man_in_tuxedo":
                if name == nil { return "manInTuxedo" }
                return "personInTuxedo"
            default:
                let uppperCamelCase = shortName.replacingOccurrences(of: "-", with: "_").components(separatedBy: "_").map(titlecase).joined(separator: "")
                return String(uppperCamelCase.unicodeScalars.first!).lowercased() + String(uppperCamelCase.unicodeScalars.dropFirst())
            }
        }

        var emoji: String {
            let unicodeComponents = unified.components(separatedBy: "-").map { Int($0, radix: 16)! }
            return unicodeComponents.map { String(UnicodeScalar($0)!) }.joined()
        }

        var hasSkinVariations: Bool { skinVariations?.isEmpty == false }
        var emojiPerSkinTone: [[SkinTone]: String]? {
            guard let skinVariations = skinVariations else { return nil }
            var emojiPerSkinTone = [[SkinTone]: String]()
            for (key, value) in skinVariations {
                let skinTones = key
                    .components(separatedBy: "-")
                    .map { SkinTone(rawValue: $0)! }
                    .reduce(into: [SkinTone]()) { result, skinTone in
                        guard !result.contains(skinTone) else { return }
                        result.append(skinTone)
                    }
                emojiPerSkinTone[skinTones] = value.emoji
            }
            return emojiPerSkinTone
        }
        var sortedEmojiPerSkinTone: [([SkinTone], String)]? {
            guard let emojiPerSkinTone = emojiPerSkinTone else { return nil }
            return emojiPerSkinTone.sorted { lhs, rhs in
                var index = 0
                while true {
                    if index >= lhs.key.count {
                        return true
                    }

                    if index >= rhs.key.count {
                        return false
                    }

                    let lhsSkinTone = lhs.key[index]
                    let rhsSkinTone = rhs.key[index]

                    if lhsSkinTone != rhsSkinTone {
                        return lhsSkinTone.sortId < rhsSkinTone.sortId
                    }

                    index += 1
                }
            }
        }

        var allowsMultipleSkinTones: Bool { hasSkinVariations && emojiPerSkinTone!.count > 5 }

        var skinToneComponents: String? {
            // There's no great way to do this except manually. Some emoji have multiple skin tones.
            // In the picker, we need to use one emoji to represent each person. For now, we manually
            // specify this. Hopefully, in the future, the data set will contain this information.
            switch shortName {
            case "two_women_holding_hands": return "[.womanStanding, .womanStanding]"
            case "two_men_holding_hands": return "[.manStanding, .manStanding]"
            case "people_holding_hands": return "[.standingPerson, .standingPerson]"
            case "couple": return "[.womanStanding, .manStanding]"
            default:
                return nil
            }
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
            fileHandle.writeLine("enum Emoji: String, CaseIterable, Equatable {")

            for emojiData in sortedEmojiData {
                fileHandle.writeLine("    case \(emojiData.enumName) = \"\(emojiData.emoji)\"")
            }

            fileHandle.writeLine("}")
        }

        // Conversion from String
        writeBlock(fileName: "EmojiWithSkinTones+String.swift") { fileHandle in
            fileHandle.writeLine("extension EmojiWithSkinTones {")

            fileHandle.writeLine("    init?(rawValue: String) {")
            fileHandle.writeLine("        guard rawValue.isSingleEmoji else { return nil }")
            fileHandle.writeLine("        switch rawValue {")

            for emojiData in sortedEmojiData {
                fileHandle.writeLine("        case \"\(emojiData.emoji)\": self.init(baseEmoji: .\(emojiData.enumName), skinTones: nil)")

                if let sortedEmojiPerSkinTone = emojiData.sortedEmojiPerSkinTone {
                    for (skinTones, emoji) in sortedEmojiPerSkinTone {
                        fileHandle.writeLine("        case \"\(emoji)\": self.init(baseEmoji: .\(emojiData.enumName), skinTones: [\(skinTones.map { ".\($0)" }.joined(separator: ", "))])")
                    }
                }
            }

            fileHandle.writeLine("        default: return nil")

            fileHandle.writeLine("        }")

            fileHandle.writeLine("    }")

            fileHandle.writeLine("}")
        }

        // Skin tones lookup
        writeBlock(fileName: "Emoji+SkinTones.swift") { fileHandle in
            fileHandle.writeLine("extension Emoji {")

            // Start SkinTone enum
            fileHandle.writeLine("    enum SkinTone: String, CaseIterable, Equatable {")
            for skinTone in SkinTone.allCases {
                fileHandle.writeLine("        case \(skinTone) = \"\(skinTone.unicodeScalar)\"")
            }

            // End SkinTone Enum
            fileHandle.writeLine("    }")

            fileHandle.writeLine("")

            // skin tone helpers
            fileHandle.writeLine("    var hasSkinTones: Bool { return emojiPerSkinTonePermutation != nil }")
            fileHandle.writeLine("    var allowsMultipleSkinTones: Bool { return hasSkinTones && skinToneComponentEmoji != nil }")

            fileHandle.writeLine("")

            // Start skinToneComponentEmoji
            fileHandle.writeLine("    var skinToneComponentEmoji: [Emoji]? {")

            fileHandle.writeLine("        switch self {")

            for emojiData in sortedEmojiData.filter({ $0.skinToneComponents != nil }) {
                fileHandle.writeLine("        case .\(emojiData.enumName): return \(emojiData.skinToneComponents!)")
            }

            fileHandle.writeLine("        default: return nil")

            fileHandle.writeLine("        }")

            // End skinToneComponentEmoji
            fileHandle.writeLine("    }")

            fileHandle.writeLine("")

            // Start emojiPerSkinTonePermutation
            fileHandle.writeLine("    var emojiPerSkinTonePermutation: [[SkinTone]: String]? {")

            fileHandle.writeLine("        switch self {")

            for emojiData in sortedEmojiData.filter({ $0.sortedEmojiPerSkinTone != nil }) {
                fileHandle.writeLine("        case .\(emojiData.enumName):")
                fileHandle.writeLine("            return [")
                for (skinTones, emoji) in emojiData.sortedEmojiPerSkinTone! {
                    fileHandle.writeLine("                [\(skinTones.map { ".\($0)" }.joined(separator: ", "))]: \"\(emoji)\",")
                }
                fileHandle.writeLine("            ]")
            }

            fileHandle.writeLine("        default: return nil")

            fileHandle.writeLine("        }")

            // End emojiPerSkinTonePermutation
            fileHandle.writeLine("    }")

            fileHandle.writeLine("}")
        }

        // Category lookup
        writeBlock(fileName: "Emoji+Category.swift") { fileHandle in
            // Start Extension
            fileHandle.writeLine("extension Emoji {")

            // Start Category enum
            fileHandle.writeLine("    enum Category: String, CaseIterable, Equatable {")
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
