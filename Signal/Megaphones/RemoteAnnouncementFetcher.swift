//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit

/// Handles fetching and parsing remote announcements.
public class RemoteAnnouncementFetcher: RemoteReleaseNotesFetcher<RemoteAnnouncementModel.Manifest, RemoteAnnouncementModel.Translation> {
    override func updatePersistedData(
        withFetchedData fetchedTranslations: [(RemoteAnnouncementModel.Manifest, RemoteAnnouncementModel.Translation)],
        transaction: DBWriteTransaction,
    ) {
        // TODO: [KC] implement!
    }

    override func fetchTranslationAndImage(
        forManifest manifest: RemoteAnnouncementModel.Manifest,
        withLocaleString localeString: String,
    ) async throws -> RemoteAnnouncementModel.Translation {
        return try await Retry.performWithBackoff(
            maxAttempts: 3,
            isRetryable: { $0.isNetworkFailureOrTimeout || $0.is5xxServiceResponse },
            block: {
                guard
                    let translationUrlPath: String = .translationUrlPath(
                        forManifestId: manifest.id,
                        withLocaleString: localeString,
                    )
                else {
                    throw OWSAssertionError("Failed to create translation URL path for manifest \(manifest.id)")
                }
                let translationParser = try await remoteReleaseNotesService.fetchTranslationParser(translationUrlPath: translationUrlPath)
                let translation = try RemoteAnnouncementModel.Translation.parseFrom(parser: translationParser)

                // TODO: [KC] May want to store whether we've downloaded media
                let _ = try await self.downloadMediaIfNecessary(
                    mediaRemoteUrlPath: translation.mediaRemoteUrlPath,
                    mediaFileDirectory: RemoteAnnouncementModel.mediaDirectory,
                    translationId: translation.id,
                )
                if manifest.id != translation.id {
                    // We shouldn't fail here, but this scenario is
                    // unexpected so let's keep an eye out for it.
                    owsFailDebug("Have manifest ID \(manifest.id) that does not match fetched translation ID \(translation.id)")
                }
                return translation
            },
        )
    }
}
