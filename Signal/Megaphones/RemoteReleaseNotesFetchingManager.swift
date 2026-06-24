//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

/// Handles fetching and parsing remote megaphones and release notes.
public class RemoteReleaseNotesFetchingManager {
    private let remoteReleaseNotesService: any RemoteReleaseNotesServiceProtocol
    private let remoteMegaphoneFetcher: RemoteMegaphoneFetcher
    private let remoteAnnouncementFetcher: RemoteAnnouncementFetcher
    private let db: DB
    private let appVersion: AppVersion
    private let tsAccountManager: TSAccountManager
    private let releaseNoteStore: ReleaseNoteStore

    init(
        db: DB,
        attachmentContentValidator: AttachmentContentValidator,
        attachmentManager: AttachmentManager,
        blockingManager: BlockingManager,
        tsAccountManager: TSAccountManager,
        notificationPresenter: NotificationPresenter,
        threadStore: ThreadStore,
        interactionStore: InteractionStore,
        appVersion: AppVersion,
        dateProvider: @escaping DateProvider,
        remoteReleaseNotesService: any RemoteReleaseNotesServiceProtocol,
        releaseNoteStore: ReleaseNoteStore,
    ) {
        self.remoteReleaseNotesService = remoteReleaseNotesService
        self.db = db
        self.appVersion = appVersion
        self.tsAccountManager = tsAccountManager
        self.releaseNoteStore = releaseNoteStore

        self.remoteMegaphoneFetcher = RemoteMegaphoneFetcher(
            db: db,
            remoteReleaseNotesService: remoteReleaseNotesService,
        )
        self.remoteAnnouncementFetcher = RemoteAnnouncementFetcher(
            db: db,
            attachmentContentValidator: attachmentContentValidator,
            attachmentManager: attachmentManager,
            blockingManager: blockingManager,
            tsAccountManager: tsAccountManager,
            notificationPresenter: notificationPresenter,
            threadStore: threadStore,
            interactionStore: interactionStore,
            dateProvider: dateProvider,
            remoteReleaseNotesService: remoteReleaseNotesService,
            releaseNoteStore: releaseNoteStore,
        )
    }

    private func filteredAnnouncementManifests(_ manifests: [RemoteAnnouncementModel.Manifest]) async throws -> [RemoteAnnouncementModel.Manifest] {
        let currentVersionNumber = try AppVersionNumber4(AppVersionNumber(appVersion.currentAppVersion))

        return db.read { tx in
            let registrationDate = tsAccountManager.registrationDate(tx: tx) ?? .distantPast
            let now = Date()
            if now.timeIntervalSince(registrationDate) < .week {
                Logger.warn("Skipping release note fetching, not enough time has passed since registration.")
                return []
            }

            let lastFetchedDate = remoteAnnouncementFetcher.lastFetchedReleaseNotes(tx: tx) ?? .distantPast
            if !BuildFlags.ReleaseNotesChannel.ignoreFetchDelay || CurrentAppContext().isRunningTests {
                if now.timeIntervalSince(lastFetchedDate) < .week {
                    Logger.warn("Skipping release note fetching, not enough time has passed since last fetch.")
                    return []
                }
            }

            // Only fetch translations for supported versions & UUIDs we have not stored before.
            return manifests.filter({
                let manifestVersion = $0.minAppVersion
                guard manifestVersion <= currentVersionNumber else {
                    Logger.warn("Ignoring release notes for unsupported version.")
                    return false
                }

                let manifest = $0
                let existingReleaseNote = releaseNoteStore.existingReleaseNoteForManifestId(manifest.id, tx: tx)

                guard existingReleaseNote == nil else {
                    Logger.warn("Ignoring release note we've already stored.")
                    return false
                }

                return true
            })
        }
    }

    /// Fetch all remote release notes currently on the service and persist them
    /// locally. Removes any locally-persisted remote release notes that are no
    /// longer available remotely.
    func syncRemoteReleaseNotes() async throws {
        Logger.info("Beginning remote release notes fetch.")

        let (megaphoneManifests, announcementManifests) = try await fetchManifests()

        let megaphoneResult = await Result {
            try await remoteMegaphoneFetcher.run(manifests: megaphoneManifests)
        }

        if case .failure(let error) = megaphoneResult {
            Logger.error("megaphone fetch failed: \(error)")
        }

        if BuildFlags.ReleaseNotesChannel.announcementFetch {
            let filteredManifests = try await filteredAnnouncementManifests(announcementManifests)
            guard filteredManifests.count > 0 else {
                return
            }

            let announcementResult = await Result {
                try await remoteAnnouncementFetcher.run(manifests: filteredManifests)
            }
            if case .failure(let error) = announcementResult {
                Logger.error("announcement fetch failed: \(error)")
            }
        }
    }

    /// Fetch the manifests for the currently-active remote megaphones.
    /// Manifests contain metadata about a megaphone, such as when it should be
    /// shown and what actions it should expose. They do not contain any
    /// user-visible content, such as strings.
    private func fetchManifests() async throws -> ([RemoteMegaphoneModel.Manifest], [RemoteAnnouncementModel.Manifest]) {
        return try await Retry.performWithBackoff(
            maxAttempts: 3,
            isRetryable: { $0.isNetworkFailureOrTimeout || $0.is5xxServiceResponse },
            block: {
                Logger.info("Fetching remote release notes manifests")
                return try await remoteReleaseNotesService.fetchManifests()
            },
        )
    }
}
