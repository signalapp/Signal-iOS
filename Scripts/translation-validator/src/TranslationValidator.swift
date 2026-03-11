//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@main
struct TranslationValidator {
    static func main() {
        let sourcePath = CommandLine.arguments.dropFirst().first!
        let sourceUrl = URL(filePath: sourcePath, relativeTo: URL.currentDirectory()).standardizedFileURL
        let sourceStrings = fetchStrings(at: sourceUrl)
        let sourceDir = sourceUrl.deletingLastPathComponent().deletingLastPathComponent()
        let enumerator = FileManager.default.enumerator(at: sourceDir, includingPropertiesForKeys: nil, errorHandler: nil)!

        var hasError = false

        var sourceSpecifiers = [String: [String]]()
        for (key, sourceString) in sourceStrings {
            do {
                sourceSpecifiers[key] = try formatSpecifiers(in: sourceString)
            } catch {
                print("The source for", key, "has a malformed format specifier:", error)
                hasError = true
            }
        }

        // Keys that only appear in the source.
        var sourceOnly = [String: Set<String>]()

        // Keys that only appear in the translations.
        var translatedOnly = [String: Set<String>]()

        for fileUrl in enumerator {
            let fileUrl = fileUrl as! URL
            if fileUrl.lastPathComponent == sourceUrl.lastPathComponent {
                let localeName = fileUrl.deletingLastPathComponent().deletingPathExtension().lastPathComponent
                let translatedStrings = fetchStrings(at: fileUrl)
                for key in Set(sourceStrings.keys).subtracting(translatedStrings.keys) {
                    sourceOnly[key, default: []].insert(localeName)
                }
                for key in Set(translatedStrings.keys).subtracting(sourceStrings.keys) {
                    translatedOnly[key, default: []].insert(localeName)
                }
                for (key, translatedString) in translatedStrings {
                    guard let sourceSpecifiers = sourceSpecifiers[key] else {
                        continue
                    }
                    let translatedSpecifiers: [String]
                    do {
                        translatedSpecifiers = try formatSpecifiers(in: translatedString)
                    } catch {
                        print("The translation for", key, "in", localeName, "has a malformed format specifier:", error)
                        hasError = true
                        continue
                    }
                    guard sourceSpecifiers.sorted() == translatedSpecifiers.sorted() else {
                        print("The translation for", key, "in", localeName, "has an incorrect set of format specifiers:", translatedSpecifiers, "vs.", sourceSpecifiers)
                        hasError = true
                        continue
                    }
                }
            }
        }

        if !sourceOnly.isEmpty {
            hasError = true
            print("The following strings are missing from some translated files:")
            for (key, localeNames) in sourceOnly.sorted(by: { $0.0 < $1.0 }) {
                print("-", key, "is missing from", localeNames.count, "language(s)")
            }
            print()
        }

        if !translatedOnly.isEmpty {
            hasError = true
            print("The following strings appear in translated files but not the source file:")
            for (key, localeNames) in translatedOnly.sorted(by: { $0.0 < $1.0 }) {
                print("-", key, "is present in", localeNames.count, "language(s)")
            }
            print()
        }

        if hasError {
            exit(1)
        }
    }

    private static func fetchStrings(at url: URL) -> [String: String] {
        return try! PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as! [String: String]
    }

    private enum FormatSpecifierError: Error {
        case notTerminated
        case unknownCharacter(Character)
        case mixOfNumberedAndUnnumbered
    }

    private static func formatSpecifiers(in formatString: String) throws -> [String] {
        var result = [String]()
        var remainingFormatString = formatString[...]
        while let range = remainingFormatString.range(of: "%") {
            remainingFormatString = remainingFormatString[range.upperBound...]
            switch remainingFormatString.first {
            case "%":
                // These can be freely added/removed, so we don't need to count them.
                remainingFormatString.removeFirst()
                continue
            case "@", "d":
                // TODO: We only have a few strings that use %d. Update them.
                result.append("@")
                remainingFormatString.removeFirst()
            case let digit? where digit.isASCII && digit.isNumber && ["$@", "$d"].contains(remainingFormatString.dropFirst().prefix(2)):
                remainingFormatString.removeFirst()
                remainingFormatString.removeFirst(2)
                result.append(String(digit))
            case let ch?:
                throw FormatSpecifierError.unknownCharacter(ch)
            case nil:
                throw FormatSpecifierError.notTerminated
            }
        }
        // If we specify %@ in the code, the translated files will use %1$@.
        if result.contains("@") {
            if result.contains(where: { $0 != "@" }) {
                throw FormatSpecifierError.mixOfNumberedAndUnnumbered
            }
            return (1...result.count).map(String.init(_:))
        }
        return result
    }
}
