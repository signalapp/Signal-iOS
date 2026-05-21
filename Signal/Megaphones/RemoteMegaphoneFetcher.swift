//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit

/// Handles fetching and parsing remote megaphones.
public class RemoteMegaphoneFetcher: RemoteReleaseNotesFetcher<RemoteMegaphoneModel.Manifest, RemoteMegaphoneModel.Translation> {
    /// Update our local persisted megaphone state with freshly-fetched
    /// megaphones from the service. Updates existing megaphones if present,
    /// and creates new ones if necessary. Removes any locally-persisted
    /// megaphones that no longer exist on the service.
    override func updatePersistedData(
        withFetchedData fetchedTranslations: [(RemoteMegaphoneModel.Manifest, RemoteMegaphoneModel.Translation)],
        transaction: DBWriteTransaction,
    ) {
        // Get the current remote megaphones.
        var localRemoteMegaphones: [String: ExperienceUpgrade] = [:]
        ExperienceUpgrade.anyEnumerate(transaction: transaction) { upgrade, _ in
            if case .remoteMegaphone = upgrade.manifest {
                localRemoteMegaphones[upgrade.uniqueId] = upgrade
            }
        }

        // Insert all megaphones we got from the service. If we already have a
        // persisted copy of this megaphone, update it - this will ensure that
        // if anything has changed about the megaphone we have the latest state.
        // For example, if the user's locale has changed we may have updated
        // translations.
        for (manifest, translation) in fetchedTranslations {
            let serviceMegaphone = RemoteMegaphoneModel(manifest: manifest, translation: translation)
            if let existingLocalMegaphone = localRemoteMegaphones[serviceMegaphone.id] {
                existingLocalMegaphone.updateManifestRemoteMegaphone(withRefetchedMegaphone: serviceMegaphone)
                existingLocalMegaphone.anyUpsert(transaction: transaction)

                localRemoteMegaphones.removeValue(forKey: serviceMegaphone.id)
            } else {
                ExperienceUpgrade
                    .makeNew(withManifest: .remoteMegaphone(megaphone: serviceMegaphone))
                    .anyInsert(transaction: transaction)
            }
        }

        // Remove records for any remaining local megaphones, which are no
        // longer on the service.
        for (_, experienceUpgradeToRemove) in localRemoteMegaphones {
            experienceUpgradeToRemove.anyRemove(transaction: transaction)
        }
    }

    /// Fetch a translation for the given manifest, using the given locale
    /// string. Retries automatically on network failure, if possible. May
    /// fail with a 404, if no translation exists for the given locale string.
    override func fetchTranslationAndImage(
        forManifest manifest: RemoteMegaphoneModel.Manifest,
        withLocaleString localeString: String,
    ) async throws -> RemoteMegaphoneModel.Translation {
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
                var translation = try RemoteMegaphoneModel.Translation.parseFrom(parser: translationParser)
                translation.setHasImage(try await self.downloadMediaIfNecessary(
                    mediaRemoteUrlPath: translation.imageRemoteUrlPath,
                    mediaFileDirectory: RemoteMegaphoneModel.imagesDirectory,
                    translationId: translation.id,
                ))
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
