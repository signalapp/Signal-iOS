//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public final class BroadcastMediaMessageJobRecord: JobRecord, FactoryInitializableFromRecordType {
    public static let defaultLabel = "BroadcastMediaMessage"

    override class var jobRecordType: JobRecordType { .broadcastMediaMessage }

    /// A map from the AttachmentStream's to upload to their corresponding list of visible copies in individual
    /// conversations. e.g. if we're broadcast-sending a picture and a video to 3 recipients, the dictionary would look
    /// like:
    ///     [
    ///         pictureAttachmentId: [
    ///             pictureCopyAttachmentIdForRecipient1,
    ///             pictureCopyAttachmentIdForRecipient2,
    ///             pictureCopyAttachmentIdForRecipient3
    ///         ],
    ///         videoAttachmentId: [
    ///             videoCopyAttachmentIdForRecipient1,
    ///             videoCopyAttachmentIdForRecipient2,
    ///             videoCopyAttachmentIdForRecipient3
    ///         ]
    ///     ]
    public let attachmentIdMap: [String: [String]]
    public let unsavedMessagesToSend: [TSOutgoingMessage]?

    public init(
        attachmentIdMap: [String: [String]],
        unsavedMessagesToSend: [TSOutgoingMessage],
        label: String,
        exclusiveProcessIdentifier: String? = nil,
        failureCount: UInt = 0,
        status: Status = .ready
    ) {
        self.attachmentIdMap = attachmentIdMap
        self.unsavedMessagesToSend = unsavedMessagesToSend

        super.init(
            label: label,
            exclusiveProcessIdentifier: exclusiveProcessIdentifier,
            failureCount: failureCount,
            status: status
        )
    }

    required init(forRecordTypeFactoryInitializationFrom decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        attachmentIdMap = try LegacySDSSerializer().deserializeLegacySDSData(
            try container.decode(Data.self, forKey: .attachmentIdMap),
            propertyName: "attachmentIdMap"
        )

        unsavedMessagesToSend = try container.decodeIfPresent(
            Data.self,
            forKey: .unsavedMessagesToSend
        ).map { unsavedMessagesToSendData in
            try LegacySDSSerializer().deserializeLegacySDSData(
                unsavedMessagesToSendData,
                propertyName: "unsavedMessagesToSend"
            )
        }

        try super.init(baseClassDuringFactoryInitializationFrom: try container.superDecoder())
    }

    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try super.encode(to: container.superEncoder())

        try container.encode(
            LegacySDSSerializer().serializeAsLegacySDSData(property: attachmentIdMap),
            forKey: .attachmentIdMap
        )

        try container.encodeIfPresent(
            LegacySDSSerializer().serializeAsLegacySDSData(property: unsavedMessagesToSend),
            forKey: .unsavedMessagesToSend
        )
    }
}
