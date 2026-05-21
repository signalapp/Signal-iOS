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

    init(
        db: DB,
        remoteReleaseNotesService: any RemoteReleaseNotesServiceProtocol,
    ) {
        self.remoteReleaseNotesService = remoteReleaseNotesService

        self.remoteMegaphoneFetcher = RemoteMegaphoneFetcher(
            db: db,
            remoteReleaseNotesService: remoteReleaseNotesService,
        )
        self.remoteAnnouncementFetcher = RemoteAnnouncementFetcher(
            db: db,
            remoteReleaseNotesService: remoteReleaseNotesService,
        )
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
            let announcementResult = await Result {
                try await remoteAnnouncementFetcher.run(manifests: announcementManifests)
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
