//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

public struct QueuedAttachmentDownloadRecord: Codable, FetchableRecord, MutablePersistableRecord {

    public typealias IDType = Int64

    /// Sqlite row id
    public var id: IDType?

    /// Id of the associated ``Attachment``.
    public let attachmentId: Attachment.IDType

    /// The priority at which to download.
    /// Determines both which goes first (higher first) and which are allowed by current settings.
    public internal(set) var priority: AttachmentDownloadPriority

    /// A given ``Attachment`` has metadata enabling downloading from
    /// many possible sources; this differentiates which should be used.
    public enum SourceType: Int, Codable, CaseIterable {
        case transitTier = 0
        case mediaTierFullsize = 1
        case mediaTierThumbnail = 2
    }

    /// Where we will be downloading the attachment from.
    public let sourceType: SourceType

    /// If the local time is not currently past this date, do not attempt to download.
    /// Used for retry backoff. Starts at nil.
    public internal(set) var minRetryTimestamp: UInt64?
    /// Number of prior retry attempts so far (starts at 0).
    public internal(set) var retryAttempts: UInt32

    /// Path to the partially downloaded file. Check the length (and existence)
    /// of the file on disk to determine how much progress has been made.
    /// Exists in the same folder as fully-downloaded attachments.
    /// TODO: unused; partial progress is not tracked/reused between app launches.
    public let partialDownloadRelativeFilePath: String

    public var partialDownloadFileUrl: URL {
        return AttachmentStream.absoluteAttachmentFileURL(
            relativeFilePath: partialDownloadRelativeFilePath
        )
    }

    // MARK: - Initializers

    public static func forNewDownload(
        ofAttachmentWithId attachmentId: Attachment.IDType,
        priority: AttachmentDownloadPriority = .default,
        sourceType: SourceType
    ) -> QueuedAttachmentDownloadRecord {
        return .init(
            id: nil,
            attachmentId: attachmentId,
            priority: priority,
            sourceType: sourceType,
            // Initial state always allows downloads.
            minRetryTimestamp: nil,
            retryAttempts: 0,
            partialDownloadRelativeFilePath: AttachmentStream.newRelativeFilePath()
        )
    }

    // MARK: - Private

    private init(
        id: Int64?,
        attachmentId: Int64,
        priority: AttachmentDownloadPriority,
        sourceType: SourceType,
        minRetryTimestamp: UInt64?,
        retryAttempts: UInt32,
        partialDownloadRelativeFilePath: String
    ) {
        self.id = id
        self.attachmentId = attachmentId
        self.priority = priority
        self.sourceType = sourceType
        self.minRetryTimestamp = minRetryTimestamp
        self.retryAttempts = retryAttempts
        self.partialDownloadRelativeFilePath = partialDownloadRelativeFilePath
    }

    // MARK: - MutablePersistableRecord

    public static let databaseTableName: String = "AttachmentDownloadQueue"

    public mutating func didInsert(with rowID: Int64, for column: String?) {
        self.id = rowID
    }

    // MARK: - Codable

    public enum CodingKeys: String, CodingKey {
        case id
        case attachmentId
        case priority
        case sourceType
        case minRetryTimestamp
        case retryAttempts
        case partialDownloadRelativeFilePath = "localRelativeFilePath"
    }
}
