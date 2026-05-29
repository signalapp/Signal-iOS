//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit

/// Handles fetching and parsing remote megaphones.
public class RemoteMegaphoneFetcher: RemoteReleaseNotesFetcher<RemoteMegaphoneModel.Manifest, RemoteMegaphoneModel.Translation> {
    private let experienceUpgradeStore: ExperienceUpgradeStore

    override init(
        db: DB,
        remoteReleaseNotesService: any RemoteReleaseNotesServiceProtocol,
    ) {
        self.experienceUpgradeStore = ExperienceUpgradeStore()

        super.init(
            db: db,
            remoteReleaseNotesService: remoteReleaseNotesService,
        )
    }

    /// Update our local persisted megaphone state with freshly-fetched
    /// megaphones from the service. Updates existing megaphones if present,
    /// and creates new ones if necessary. Removes any locally-persisted
    /// megaphones that no longer exist on the service.
    override func updatePersistedData(
        withFetchedData fetchedTranslations: [(RemoteMegaphoneModel.Manifest, RemoteMegaphoneModel.Translation)],
        transaction tx: DBWriteTransaction,
    ) {
        // Get any persisted ExperienceUpgrades for the remote megaphones.
        var experienceUpgradesByMegaphoneId: [String: ExperienceUpgrade] = [:]
        experienceUpgradeStore.enumerateExperienceUpgrades(tx: tx) { experienceUpgrade in
            guard case .remoteMegaphone(let model) = experienceUpgrade.manifest else {
                return
            }

            experienceUpgradesByMegaphoneId[model.manifest.id] = experienceUpgrade
        }

        // Insert all megaphones we got from the service. If we already have a
        // persisted copy of this megaphone, update it - this will ensure that
        // if anything has changed about the megaphone we have the latest state.
        // For example, if the user's locale has changed we may have updated
        // translations.
        for (manifest, translation) in fetchedTranslations {
            let remoteMegaphoneModel = RemoteMegaphoneModel(manifest: manifest, translation: translation)
            let experienceUpgrade: ExperienceUpgrade
            if let persisted = experienceUpgradesByMegaphoneId.removeValue(forKey: manifest.id) {
                experienceUpgrade = persisted
            } else {
                experienceUpgrade = .makeNew(withManifest: .remoteMegaphone(megaphone: remoteMegaphoneModel))
            }

            experienceUpgradeStore.upsertRemoteMegaphone(
                experienceUpgrade: experienceUpgrade,
                newRemoteMegaphoneModel: remoteMegaphoneModel,
                tx: tx,
            )
        }

        // Remove records for any remaining local megaphones, which are no
        // longer on the service.
        for (_, experienceUpgradeToRemove) in experienceUpgradesByMegaphoneId {
            experienceUpgradeStore.remove(
                experienceUpgrade: experienceUpgradeToRemove,
                tx: tx,
            )
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
