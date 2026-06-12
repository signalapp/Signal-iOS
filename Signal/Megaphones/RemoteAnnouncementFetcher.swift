//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit

/// Handles fetching and parsing remote announcements.
public class RemoteAnnouncementFetcher: RemoteReleaseNotesFetcher<RemoteAnnouncementModel.Manifest, RemoteAnnouncementModel.Translation> {
    private let attachmentContentValidator: AttachmentContentValidator
    private let attachmentManager: AttachmentManager
    private let blockingManager: BlockingManager
    private let tsAccountManager: TSAccountManager
    private let notificationPresenter: NotificationPresenter
    private let threadStore: ThreadStore
    private let interactionStore: InteractionStore
    private let dateProvider: DateProvider
    private let kvStore: NewKeyValueStore
    private let lastFetchedReleaseNotesKey = "lastFetchedReleaseNotes"

    init(
        db: any DB,
        attachmentContentValidator: AttachmentContentValidator,
        attachmentManager: AttachmentManager,
        blockingManager: BlockingManager,
        tsAccountManager: TSAccountManager,
        notificationPresenter: NotificationPresenter,
        threadStore: ThreadStore,
        interactionStore: InteractionStore,
        dateProvider: @escaping DateProvider,
        remoteReleaseNotesService: any RemoteReleaseNotesServiceProtocol,
    ) {
        self.attachmentContentValidator = attachmentContentValidator
        self.attachmentManager = attachmentManager
        self.blockingManager = blockingManager
        self.tsAccountManager = tsAccountManager
        self.notificationPresenter = notificationPresenter
        self.threadStore = threadStore
        self.interactionStore = interactionStore
        self.dateProvider = dateProvider
        self.kvStore = NewKeyValueStore(collection: "RemoteReleaseNotes")

        super.init(db: db, remoteReleaseNotesService: remoteReleaseNotesService)
    }

    private func getOrCreateThread(tx: DBWriteTransaction) -> TSReleaseNotesThread {
        if
            let releaseNotesThread = threadStore.fetchThread(
                uniqueId: TSReleaseNotesThread.releaseNotesUniqueId,
                tx: tx,
            ) as? TSReleaseNotesThread
        {
            return releaseNotesThread
        }
        return TSReleaseNotesThread.createReleaseNotes(transaction: tx)
    }

    override func updatePersistedData(
        withFetchedData fetchedTranslations: [(RemoteAnnouncementModel.Manifest, RemoteAnnouncementModel.Translation)],
    ) async throws {
        guard let localIdentifiers = tsAccountManager.localIdentifiersWithMaybeSneakyTransaction else {
            return
        }

        // Sort by lowest to highest min version. We will show the first eligible release note we haven't already shown.
        let sortedFetchedTranslations = fetchedTranslations.sorted(by: { $0.0.minAppVersion < $1.0.minAppVersion })

        for fetched in sortedFetchedTranslations {
            let (manifest, translation) = fetched
            if let countries = manifest.countries {
                guard
                    RemoteConfig.isCountryCodeBucketEnabled(
                        csvString: countries,
                        key: manifest.id,
                        localIdentifiers: localIdentifiers,
                    )
                else {
                    continue
                }
            }

            var pendingAttachment: PendingAttachment?
            if translation.hasImage {
                guard let mediaFileUrl: URL = .mediaFilePath(dirUrl: RemoteAnnouncementModel.mediaDirectory, mediaLocalRelativePath: translation.id) else {
                    throw OWSAssertionError("Failed to get image file path for translation with ID \(translation.id)")
                }

                // Now that its moved to the attachment_files dir, we can remove it from its temporary download location, so .owned is safe.
                let dataSourcePath = DataSourcePath(fileUrl: mediaFileUrl, ownership: .owned)
                let mimeType = translation.mediaMimeType ?? "image/webp"
                pendingAttachment = try await attachmentContentValidator.validateDataSourceContents(
                    dataSourcePath,
                    mimeType: mimeType,
                    renderingFlag: .default,
                    sourceFilename: nil,
                )
            }

            let validatedMessageBody = try await attachmentContentValidator.prepareOversizeTextIfNeeded(
                MessageBody(
                    text: translation.title + "\n\n" + translation.body,
                    ranges: MessageBodyRanges(
                        mentions: [:],
                        styles: [.init(.bold, range: NSRange(location: 0, length: (translation.title as NSString).length))],
                    ),
                ),
            )

            try await db.awaitableWrite { tx in
                let releaseNotesThread = getOrCreateThread(tx: tx)
                // TODO: implement blocking for the release notes thread
                guard !blockingManager.isThreadBlocked(releaseNotesThread, transaction: tx) else {
                    Logger.info("Skipping release notes update: thread is blocked")
                    storeReleaseNoteAndUpdateLastFetchTime(uniqueId: manifest.id, tx: tx)
                    return
                }

                let releaseNotesMessage = TSReleaseNotesMessage(
                    thread: releaseNotesThread,
                    messageBody: validatedMessageBody,
                    timestamp: MessageTimestampGenerator.sharedInstance.generateTimestamp(),
                )
                interactionStore.insertInteraction(releaseNotesMessage, tx: tx)

                if let pendingAttachment {
                    let ownerBuilder: AttachmentReference.OwnerBuilder = .messageBodyAttachment(
                        .init(
                            messageRowId: releaseNotesMessage.sqliteRowId!,
                            receivedAtTimestamp: releaseNotesMessage.receivedAtTimestamp,
                            threadRowId: releaseNotesThread.sqliteRowId!,
                            isViewOnce: false,
                            isPastEditRevision: false,
                            orderInMessage: 0,
                        ),
                    )

                    let _ = try attachmentManager.createAttachmentStream(
                        from: OwnedAttachmentDataSource(
                            dataSource: .pendingAttachment(pendingAttachment),
                            owner: ownerBuilder,
                        ),
                        tx: tx,
                    )
                }
                notificationPresenter.notifyUser(
                    forReleaseNotesMessage: releaseNotesMessage,
                    thread: releaseNotesThread,
                    transaction: tx,
                )
                storeReleaseNoteAndUpdateLastFetchTime(uniqueId: manifest.id, tx: tx)
            }

            // There may be more than one release note, but we will only show the first eligible one.
            return
        }
        // TODO: [KC] implement boost message
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
                var translation = try await remoteReleaseNotesService.fetchAnnouncementTranslation(translationUrlPath: translationUrlPath)
                let hasImage = try await self.downloadMediaIfNecessary(
                    mediaRemoteUrlPath: translation.mediaRemoteUrlPath,
                    mediaFileDirectory: RemoteAnnouncementModel.mediaDirectory,
                    translationId: translation.id,
                )
                translation.hasImage = hasImage

                if manifest.id != translation.id {
                    // We shouldn't fail here, but this scenario is
                    // unexpected so let's keep an eye out for it.
                    owsFailDebug("Have manifest ID \(manifest.id) that does not match fetched translation ID \(translation.id)")
                }
                return translation
            },
        )
    }

    func updateLastFetchedReleaseNotes(_ value: Date, tx: DBWriteTransaction) {
        kvStore.writeValue(value, forKey: lastFetchedReleaseNotesKey, tx: tx)
    }

    func lastFetchedReleaseNotes(tx: DBReadTransaction) -> Date? {
        kvStore.fetchValue(Date.self, forKey: lastFetchedReleaseNotesKey, tx: tx)
    }

    func storeReleaseNoteAndUpdateLastFetchTime(uniqueId: String, tx: DBWriteTransaction) {
        failIfThrows {
            try StoredReleaseNote(uniqueId: uniqueId).insert(tx.database)
        }
        updateLastFetchedReleaseNotes(dateProvider(), tx: tx)
    }
}
