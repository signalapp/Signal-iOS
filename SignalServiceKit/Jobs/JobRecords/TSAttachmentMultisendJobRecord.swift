//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public final class TSAttachmentMultisendJobRecord: JobRecord, FactoryInitializableFromRecordType {
    override class var jobRecordType: JobRecordType { .tsAttachmentMultisend }

    /// A map from the TSAttachmentStream's to upload to their corresponding list of visible copies in individual
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

    // These have always been only OutgoingStoryMessages, but rather than touch the serialization
    // layer, we just transform them in memory.
    // This class's public API takes OutgoingStoryMessage(s) and returns OutgoingStoryMessage(s).
    private let unsavedMessagesToSend: [TSOutgoingMessage]?

    public var storyMessagesToSend: [OutgoingStoryMessage]? {
        return unsavedMessagesToSend?.compactMap { $0 as? OutgoingStoryMessage }
    }

    public init(
        attachmentIdMap: [String: [String]],
        storyMessagesToSend: [OutgoingStoryMessage]?,
        failureCount: UInt = 0,
        status: Status = .ready
    ) {
        self.attachmentIdMap = attachmentIdMap
        self.unsavedMessagesToSend = storyMessagesToSend

        super.init(
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
