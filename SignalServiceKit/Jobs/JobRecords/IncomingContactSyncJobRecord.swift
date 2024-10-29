//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public final class IncomingContactSyncJobRecord: JobRecord, FactoryInitializableFromRecordType {
    override class var jobRecordType: JobRecordType { .incomingContactSync }

    private let legacyAttachmentId: String?

    private let cdnNumber: UInt32?
    private let cdnKey: String?
    private let encryptionKey: Data?
    private let digest: Data?
    private let plaintextLength: UInt32?

    public enum DownloadInfo {
        case invalid
        case legacy(attachmentId: String)
        case transient(AttachmentDownloads.DownloadMetadata)
    }

    public var downloadInfo: DownloadInfo {
        if
            let cdnKey,
            let cdnNumber,
            let encryptionKey,
            let digest,
            let plaintextLength
        {
            return .transient(.init(
                mimeType: MimeType.applicationOctetStream.rawValue,
                cdnNumber: cdnNumber,
                encryptionKey: encryptionKey,
                source: .transitTier(
                    cdnKey: cdnKey,
                    digest: digest,
                    plaintextLength: plaintextLength
                )
            ))
        }
        owsAssertDebug(
            cdnKey == nil
            && cdnNumber == nil
            && encryptionKey == nil
            && digest == nil
            && plaintextLength == nil,
            "Either all fields should be set or none!"
        )
        if let legacyAttachmentId {
            return .legacy(attachmentId: legacyAttachmentId)
        }
        return .invalid
    }

    public let isCompleteContactSync: Bool

    public static func legacy(
        legacyAttachmentId: String?,
        isCompleteContactSync: Bool,
        failureCount: UInt = 0,
        status: Status = .ready
    ) -> IncomingContactSyncJobRecord {
        return IncomingContactSyncJobRecord(
            legacyAttachmentId: legacyAttachmentId,
            cdnNumber: nil,
            cdnKey: nil,
            encryptionKey: nil,
            digest: nil,
            plaintextLength: nil,
            isCompleteContactSync: isCompleteContactSync,
            failureCount: failureCount,
            status: status
        )
    }

    public convenience init(
        cdnNumber: UInt32,
        cdnKey: String,
        encryptionKey: Data,
        digest: Data,
        plaintextLength: UInt32?,
        isCompleteContactSync: Bool
    ) {
        self.init(
            legacyAttachmentId: nil,
            cdnNumber: cdnNumber,
            cdnKey: cdnKey,
            encryptionKey: encryptionKey,
            digest: digest,
            plaintextLength: plaintextLength,
            isCompleteContactSync: isCompleteContactSync
        )
    }

    private init(
        legacyAttachmentId: String?,
        cdnNumber: UInt32?,
        cdnKey: String?,
        encryptionKey: Data?,
        digest: Data?,
        plaintextLength: UInt32?,
        isCompleteContactSync: Bool,
        failureCount: UInt = 0,
        status: Status = .ready
    ) {
        self.legacyAttachmentId = legacyAttachmentId
        self.isCompleteContactSync = isCompleteContactSync

        self.cdnNumber = cdnNumber
        self.cdnKey = cdnKey
        self.encryptionKey = encryptionKey
        self.digest = digest
        self.plaintextLength = plaintextLength

        super.init(
            failureCount: failureCount,
            status: status
        )
    }

    required init(forRecordTypeFactoryInitializationFrom decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        legacyAttachmentId = try container.decodeIfPresent(String.self, forKey: .legacyAttachmentId)

        cdnNumber = try container.decodeIfPresent(UInt32.self, forKey: .ICSJR_cdnNumber)
        cdnKey = try container.decodeIfPresent(String.self, forKey: .ICSJR_cdnKey)
        encryptionKey = try container.decodeIfPresent(Data.self, forKey: .ICSJR_encryptionKey)
        digest = try container.decodeIfPresent(Data.self, forKey: .ICSJR_digest)
        plaintextLength = try container.decodeIfPresent(UInt32.self, forKey: .ICSJR_plaintextLength)

        isCompleteContactSync = try container.decode(Bool.self, forKey: .isCompleteContactSync)

        try super.init(baseClassDuringFactoryInitializationFrom: container.superDecoder())
    }

    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try super.encode(to: container.superEncoder())

        try container.encodeIfPresent(legacyAttachmentId, forKey: .legacyAttachmentId)

        try container.encodeIfPresent(cdnNumber, forKey: .ICSJR_cdnNumber)
        try container.encodeIfPresent(cdnKey, forKey: .ICSJR_cdnKey)
        try container.encodeIfPresent(encryptionKey, forKey: .ICSJR_encryptionKey)
        try container.encodeIfPresent(digest, forKey: .ICSJR_digest)
        try container.encodeIfPresent(plaintextLength, forKey: .ICSJR_plaintextLength)

        try container.encode(isCompleteContactSync, forKey: .isCompleteContactSync)
    }
}
