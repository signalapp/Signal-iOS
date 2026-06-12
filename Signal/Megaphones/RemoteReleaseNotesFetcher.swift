//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

private extension Array<String> {
    /// A list of possible locale strings for which a translation may be
    /// available, based on the user's current locale. Includes a fallback to
    /// English.
    static var possibleTranslationLocaleStrings: [String] {
        var locales: [String] = []

        if let langCode = Locale.current.languageCode {
            locales.append(langCode)

            if let regionCode = Locale.current.regionCode {
                locales.append("\(langCode)_\(regionCode)")
            }
        }

        // Always include English at the end, as a fallback. This translation
        // should always exist.
        return locales + ["en"]
    }
}

extension String {
    /// The path at which a translation may be found, for the given manifest
    /// and locale string.
    static func translationUrlPath(
        forManifestId manifestId: String,
        withLocaleString localeString: String,
    ) -> String? {
        "static/release-notes/\(manifestId)/\(localeString).json"
            .percentEncodedAsUrlPath
    }
}

// MARK: URLs

extension URL {
    static func mediaFilePath(dirUrl: URL, mediaLocalRelativePath: String) -> URL? {
        guard OWSFileSystem.ensureDirectoryExists(dirUrl.path) else {
            return nil
        }

        return dirUrl.appendingPathComponent(mediaLocalRelativePath)
    }
}

public class RemoteReleaseNotesFetcher<ManifestType, TranslationType> {
    let db: DB
    let remoteReleaseNotesService: any RemoteReleaseNotesServiceProtocol
    var fetchedTranslations: [(ManifestType, TranslationType)] = []

    init(
        db: DB,
        remoteReleaseNotesService: any RemoteReleaseNotesServiceProtocol,
    ) {
        self.db = db
        self.remoteReleaseNotesService = remoteReleaseNotesService
    }

    func run(manifests: [ManifestType]) async throws {
        fetchedTranslations = try await withThrowingTaskGroup(of: (ManifestType, TranslationType).self) { taskGroup in
            for manifest in manifests {
                taskGroup.addTask {
                    let translation = try await self.fetchTranslation(forManifest: manifest)
                    return (manifest, translation)
                }
            }
            return try await taskGroup.reduce(into: [], { $0.append($1) })
        }
        try await updatePersistedData(withFetchedData: fetchedTranslations)
    }

    /// Fetch user-displayable localized strings for the given manifest. Will
    /// attempt to fetch a translation matching the user's current locale,
    /// falling back to English otherwise.
    private func fetchTranslation(
        forManifest manifest: ManifestType,
    ) async throws -> TranslationType {
        let localeStrings: [String] = .possibleTranslationLocaleStrings

        for (index, localeString) in localeStrings.enumerated() {
            do {
                return try await fetchTranslationAndImage(forManifest: manifest, withLocaleString: localeString)
            } catch let error as OWSHTTPError where error.responseStatusCode == 404 && (index + 1) != localeStrings.endIndex {
                // If this isn't the last locale & it's not found, try the next one.
                continue
            }
            // If we hit a non-404 error, propagate it out immediately.
        }

        // We either return a value or throw an error in the loop as long as there
        // is at least one locale.
        throw OWSAssertionError("Unexpectedly found no locale strings!")
    }

    /// Downloads the image if necessary.
    ///
    /// Doesn't perform any network requests if the image has already been
    /// downloaded.
    ///
    /// - Throws: If the image should be downloaded but can't be downloaded.
    /// - Returns: Whether or not `translation` has an image.
    func downloadMediaIfNecessary(
        mediaRemoteUrlPath: String?,
        mediaFileDirectory: URL,
        translationId: String,
    ) async throws -> Bool {
        guard let mediaRemoteUrlPath else {
            return false
        }

        guard let mediaFileUrl: URL = .mediaFilePath(dirUrl: mediaFileDirectory, mediaLocalRelativePath: translationId) else {
            throw OWSAssertionError("Failed to get image file path for translation with ID \(translationId)")
        }

        return try await Retry.performWithBackoff(
            maxAttempts: 3,
            isRetryable: { $0.isNetworkFailureOrTimeout || $0.is5xxServiceResponse },
            block: {
                try await remoteReleaseNotesService.downloadMedia(
                    mediaRemoteUrlPath: mediaRemoteUrlPath,
                    mediaFileUrl: mediaFileUrl,
                    translationId: translationId,
                )
            },
        )
    }

    func fetchTranslationAndImage(
        forManifest manifest: ManifestType,
        withLocaleString localeString: String,
    ) async throws -> TranslationType {
        owsFail("Must override fetch")
    }

    func updatePersistedData(withFetchedData fetchedTranslations: [(ManifestType, TranslationType)]) async throws {
        owsFail("Must override updatePersistedData")
    }
}
