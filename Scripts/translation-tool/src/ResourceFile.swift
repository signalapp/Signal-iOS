//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// Maps Smartling language codes to .strings/.stringsdict language codes.
private let languageMap: [String: String] = [
    "ar": "ar",
    "bn-BD": "bn",
    "ca": "ca",
    "cs": "cs",
    "da": "da",
    "de": "de",
    "el": "el",
    "es": "es",
    "fa-IR": "fa",
    "fi": "fi",
    "fr": "fr",
    "ga-IE": "ga",
    "gu-IN": "gu",
    "he": "he",
    "hi-IN": "hi",
    "hr-HR": "hr",
    "hu": "hu",
    "id": "id",
    "it": "it",
    "ja": "ja",
    "ko": "ko",
    "mr-IN": "mr",
    "ms": "ms",
    "nb": "nb",
    "nl": "nl",
    "pl": "pl",
    "pt-BR": "pt_BR",
    "pt-PT": "pt_PT",
    "ro-RO": "ro",
    "ru": "ru",
    "sk-SK": "sk",
    "sr-YR": "sr",
    "sv": "sv",
    "th": "th",
    "tr": "tr",
    "uk-UA": "uk",
    "ur": "ur",
    "vi": "vi",
    "zh-CN": "zh_CN",
    "zh-HK": "zh_HK",
    "zh-TW": "zh_TW"
]

struct ResourceFile: TranslatableFile {
    var filename: String

    var relativeSourcePath: String {
        "\(Self.relativeDirectoryPath)/en.lproj/\(filename)"
    }

    private static let relativeDirectoryPath = "Signal/translations"

    private func relativePath(for languageCode: String) -> String {
        return "\(Self.relativeDirectoryPath)/\(languageCode).lproj/\(filename)"
    }

    func downloadAllTranslations(to repositoryURL: URL, using client: Smartling) async throws {
        try await withLimitedThrowingTaskGroup(limit: Constant.concurrentRequestLimit) { taskGroup in
            for (remoteIdentifier, localIdentifier) in languageMap {
                let fileURL = try await client.downloadTranslatedFile(for: filename, in: remoteIdentifier)
                let localRelativePath = relativePath(for: localIdentifier)
                try FileManager.default.copyItem(
                    at: fileURL,
                    replacingItemAt: repositoryURL.appendingPathComponent(localRelativePath)
                )
                print("Saved \(localRelativePath)")
            }
        }
    }

    static func checkForUnusedLocalizations(in repositoryURL: URL) throws {
        try checkForUnusedLocalizations(
            in: repositoryURL.appendingPathComponent(relativeDirectoryPath),
            suffix: ".lproj",
            expectedLocalizations: languageMap.map { $1 } + ["en"]
        )
    }
}
