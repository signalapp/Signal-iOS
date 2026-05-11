//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public final class IncomingContactSyncJobRecord: JobRecord {
    override public class var jobRecordType: JobRecordType { .incomingContactSync }

    private let cdnNumber: UInt32?
    private let cdnKey: String?
    private let encryptionKey: Data?
    private let digest: Data?
    private let plaintextLength: UInt32?

    public enum DownloadInfo {
        case invalid
        case transient(downloadMetadata: AttachmentDownloads.DownloadMetadata, decryptionMetadata: DecryptionMetadata)
    }

    public var downloadInfo: DownloadInfo {
        guard
            let cdnKey,
            let cdnNumber,
            let encryptionKey,
            let digest,
            let plaintextLength
        else {
            owsAssertDebug(
                cdnKey == nil
                    && cdnNumber == nil
                    && encryptionKey == nil
                    && digest == nil
                    && plaintextLength == nil,
                "Either all fields should be set or none!",
            )
            return .invalid
        }
        guard let attachmentKey = try? AttachmentKey(combinedKey: encryptionKey) else {
            owsFailDebug("couldn't parse contact sync attachment key")
            return .invalid
        }
        return .transient(
            downloadMetadata: AttachmentDownloads.DownloadMetadata(
                cdnNumber: cdnNumber,
                source: .transitTier(cdnKey: cdnKey),
            ),
            decryptionMetadata: DecryptionMetadata(
                key: attachmentKey,
                integrityCheck: .ciphertextDigest(digest),
                plaintextLength: UInt64(safeCast: plaintextLength),
            ),
        )
    }

    public let isCompleteContactSync: Bool

    public init(
        cdnNumber: UInt32,
        cdnKey: String,
        attachmentKey: AttachmentKey,
        digest: Data,
        plaintextLength: UInt32,
        isCompleteContactSync: Bool,
        failureCount: UInt = 0,
        status: Status = .ready,
    ) {
        self.isCompleteContactSync = isCompleteContactSync

        self.cdnNumber = cdnNumber
        self.cdnKey = cdnKey
        self.encryptionKey = attachmentKey.combinedKey
        self.digest = digest
        self.plaintextLength = plaintextLength

        super.init(
            failureCount: failureCount,
            status: status,
        )
    }

#if TESTABLE_BUILD
    public init(
        cdnNumber: UInt32?,
        cdnKey: String?,
        encryptionKey: Data?,
        digest: Data?,
        plaintextLength: UInt32?,
        isCompleteContactSync: Bool,
        failureCount: UInt = 0,
        status: Status = .ready,
    ) {
        self.isCompleteContactSync = isCompleteContactSync

        self.cdnNumber = cdnNumber
        self.cdnKey = cdnKey
        self.encryptionKey = encryptionKey
        self.digest = digest
        self.plaintextLength = plaintextLength

        super.init(
            failureCount: failureCount,
            status: status,
        )
    }
#endif

    required init(inheritableDecoder decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        cdnNumber = try container.decodeIfPresent(UInt32.self, forKey: .ICSJR_cdnNumber)
        cdnKey = try container.decodeIfPresent(String.self, forKey: .ICSJR_cdnKey)
        encryptionKey = try container.decodeIfPresent(Data.self, forKey: .ICSJR_encryptionKey)
        digest = try container.decodeIfPresent(Data.self, forKey: .ICSJR_digest)
        plaintextLength = try container.decodeIfPresent(UInt32.self, forKey: .ICSJR_plaintextLength)

        isCompleteContactSync = try container.decode(Bool.self, forKey: .isCompleteContactSync)

        try super.init(inheritableDecoder: decoder)
    }

    override public func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(cdnNumber, forKey: .ICSJR_cdnNumber)
        try container.encodeIfPresent(cdnKey, forKey: .ICSJR_cdnKey)
        try container.encodeIfPresent(encryptionKey, forKey: .ICSJR_encryptionKey)
        try container.encodeIfPresent(digest, forKey: .ICSJR_digest)
        try container.encodeIfPresent(plaintextLength, forKey: .ICSJR_plaintextLength)
        try container.encode(isCompleteContactSync, forKey: .isCompleteContactSync)
    }
}
