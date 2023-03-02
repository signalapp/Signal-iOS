//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// Maps Smartling language codes to App Store Connect language codes.
private let languageMap: [String: [String]] = [
    // These languages are returned from Smartling and need to be moved to their correct final destination.
    "ar": ["ar-SA"],
    "ca": ["ca"],
    "cs": ["cs"],
    "da": ["da"],
    "de": ["de-DE"],
    "el": ["el"],
    "es": ["es-ES", "es-MX"],
    "fi": ["fi"],
    "fr": ["fr-CA", "fr-FR"],
    "he": ["he"],
    "hi-IN": ["hi"],
    "hr-HR": ["hr"],
    "hu": ["hu"],
    "id": ["id"],
    "it": ["it"],
    "ja": ["ja"],
    "ko": ["ko"],
    "ms": ["ms"],
    "nb": ["no"],
    "nl": ["nl-NL"],
    "pl": ["pl"],
    "pt-BR": ["pt-BR"],
    "pt-PT": ["pt-PT"],
    "ro-RO": ["ro"],
    "ru": ["ru"],
    "sk-SK": ["sk"],
    "sv": ["sv"],
    "th": ["th"],
    "tr": ["tr"],
    "uk-UA": ["uk"],
    "vi": ["vi"],
    "zh-CN": ["zh-Hans"],
    "zh-HK": ["zh-Hant"]

    // These don't exist in App Store Connect, so there's no need to fetch them from Smartling.
    // "bn-BD": [],
    // "fa-IR": [],
    // "ga-IE": [],
    // "gu-IN": [],
    // "mr-IN": [],
    // "sr-YR": [],
    // "ug": [],
    // "ur": [],
    // "yue": [],
    // "zh-TW": [],
]

private let extraEnglishLanguages: [String] = ["en-AU", "en-CA", "en-GB"]

struct MetadataFile: TranslatableFile {
    var filename: String

    var relativeSourcePath: String { relativePath(for: "en-US") }

    private static let relativeDirectoryPath = "fastlane/metadata"

    private func relativePath(for languageCode: String) -> String {
        return "\(Self.relativeDirectoryPath)/\(languageCode)/\(filename)"
    }

    func downloadAllTranslations(to repositoryURL: URL, using client: Smartling) async throws {
        try await withLimitedThrowingTaskGroup(limit: Constant.concurrentRequestLimit) { taskGroup in
            try await taskGroup.addTask {
                // English is special. Instead of downloading a file, we copy the file we
                // uploaded to other English languages.
                let fileURL = repositoryURL.appendingPathComponent(relativeSourcePath)
                try processDownloadedFile(at: fileURL, repositoryURL: repositoryURL, localIdentifiers: extraEnglishLanguages)
            }
            for (remoteIdentifier, localIdentifiers) in languageMap {
                try await taskGroup.addTask {
                    let fileURL = try await client.downloadTranslatedFile(for: filename, in: remoteIdentifier)
                    try processDownloadedFile(at: fileURL, repositoryURL: repositoryURL, localIdentifiers: localIdentifiers)
                }
            }
        }
    }

    private func processDownloadedFile(at fileURL: URL, repositoryURL: URL, localIdentifiers: [String]) throws {
        for localIdentifier in localIdentifiers {
            let localRelativePath = relativePath(for: localIdentifier)
            try FileManager.default.copyItem(
                at: fileURL,
                replacingItemAt: repositoryURL.appendingPathComponent(localRelativePath)
            )
            print("Saved \(localRelativePath)")
        }
    }

    static func checkForUnusedLocalizations(in repositoryURL: URL) throws {
        try checkForUnusedLocalizations(
            in: repositoryURL.appendingPathComponent(Self.relativeDirectoryPath),
            suffix: "",
            expectedLocalizations: languageMap.flatMap { $1 } + extraEnglishLanguages + ["en-US"]
        )
    }
}
