//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

protocol TranslatableFile {
    var filename: String { get }
    var relativeSourcePath: String { get }

    /// Checks if there are localizations without a remote counterpart.
    ///
    /// This is most useful when adding or removing languages.
    static func checkForUnusedLocalizations(in repositoryURL: URL) throws

    /// Downloads translations for all languages.
    func downloadAllTranslations(to repositoryURL: URL, using client: Smartling) async throws
}

extension TranslatableFile {

    /// Compares localization directories on disk against what's expected.
    ///
    /// If there are localization directories on disk that aren't being updated
    /// by this script, that likely means we're shipping stale translations. We
    /// check this each time we download translations.
    static func checkForUnusedLocalizations(in directoryURL: URL, suffix: String, expectedLocalizations: [String]) throws {
        let localLocalizationCodes = try fetchLocalLocalizationCodes(in: directoryURL, suffix: suffix)
        let unusedLocalizationCodes = localLocalizationCodes.subtracting(expectedLocalizations)

        guard unusedLocalizationCodes.isEmpty else {
            let sortedLocalizationCodes = unusedLocalizationCodes.sorted(by: <)
            print("We're shipping languages that aren't pulling translations: \(sortedLocalizationCodes)")
            print("(stored in \(directoryURL.path))")
            exit(1)
        }
    }

    private static func fetchLocalLocalizationCodes(in directoryURL: URL, suffix: String) throws -> Set<String> {
        var result = Set<String>()
        for filename in try FileManager.default.contentsOfDirectory(atPath: directoryURL.path) {
            guard filename.hasSuffix(suffix) else {
                continue
            }
            result.insert(String(filename.dropLast(suffix.count)))
        }
        return result
    }
}
