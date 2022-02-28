//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB
import SignalClient
import UIKit

public struct StoryMessageRecord: Dependencies, Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "story_messages"

    public var id: Int64?

    public let timestamp: UInt64
    public let authorUuid: UUID
    public let groupId: Data?

    public enum Direction: Int, Codable { case incoming = 0, outgoing = 1 }
    public let direction: Direction

    public let manifest: StoryManifest

    public let attachment: StoryMessageAttachment

    public var allAttachmentIds: [String] {
        switch attachment {
        case .file(let attachmentId):
            return [attachmentId]
        case .text(let attachment):
            if let preview = attachment.preview, let imageAttachmentId = preview.imageAttachmentId {
                return [imageAttachmentId]
            } else {
                return []
            }
        }
    }

    public static var databaseUUIDEncodingStrategy: DatabaseUUIDEncodingStrategy { .string }

    public init(
        timestamp: UInt64,
        authorUuid: UUID,
        groupId: Data?,
        manifest: StoryManifest,
        attachment: StoryMessageAttachment
    ) {
        self.timestamp = timestamp
        self.authorUuid = authorUuid
        self.groupId = groupId
        switch manifest {
        case .incoming:
            self.direction = .incoming
        case .outgoing:
            self.direction = .outgoing
        }
        self.manifest = manifest
        self.attachment = attachment
    }

    @discardableResult
    public static func create(
        withIncomingStoryMessage storyMessage: SSKProtoStoryMessage,
        timestamp: UInt64,
        author: SignalServiceAddress,
        transaction: SDSAnyWriteTransaction
    ) throws -> StoryMessageRecord {
        Logger.info("Processing StoryMessage from \(author) with timestamp \(timestamp)")

        guard let authorUuid = author.uuid else {
            throw OWSAssertionError("Author is missing UUID")
        }

        let groupId: Data?
        if let masterKey = storyMessage.group?.masterKey {
            let groupContext = try Self.groupsV2.groupV2ContextInfo(forMasterKeyData: masterKey)
            groupId = groupContext.groupId
        } else {
            groupId = nil
        }

        if let groupId = groupId, blockingManager.isGroupIdBlocked(groupId) {
            throw OWSGenericError("Ignoring StoryMessage in blocked group.")
        } else if blockingManager.isAddressBlocked(author) {
            throw OWSGenericError("Ignoring StoryMessage from blocked author.")
        }

        let manifest = StoryManifest.incoming(allowsReplies: storyMessage.allowsReplies, viewed: false)

        let attachment: StoryMessageAttachment
        if let fileAttachment = storyMessage.fileAttachment {
            guard let attachmentPointer = TSAttachmentPointer(fromProto: fileAttachment, albumMessage: nil) else {
                throw OWSAssertionError("Invalid file attachment for StoryMessage.")
            }
            attachmentPointer.anyInsert(transaction: transaction)
            attachment = .file(attachmentId: attachmentPointer.uniqueId)
        } else if let textAttachmentProto = storyMessage.textAttachment {
            attachment = .text(attachment: try TextAttachment(from: textAttachmentProto, transaction: transaction))
        } else {
            throw OWSAssertionError("Missing attachment for StoryMessage.")
        }

        var record = StoryMessageRecord(
            timestamp: timestamp,
            authorUuid: authorUuid,
            groupId: groupId,
            manifest: manifest,
            attachment: attachment
        )
        try record.insert(transaction.unwrapGrdbWrite.database)

        return record
    }

    mutating public func didInsert(with rowID: Int64, for column: String?) {
        self.id = rowID
    }
}

public enum StoryManifest: Codable {
    case incoming(allowsReplies: Bool, viewed: Bool)
    case outgoing(manifest: [UUID: StoryRecipientState])
}

public struct StoryRecipientState: Codable {
    typealias DistributionListId = String

    let allowsReplies: Bool
    let contexts: [DistributionListId]
    let hasViewed: Bool
}

public enum StoryMessageAttachment: Codable {
    case file(attachmentId: String)
    case text(attachment: TextAttachment)
}

public struct TextAttachment: Codable {
    public let text: String

    public enum TextStyle: Int, Codable {
        case regular = 0
        case bold = 1
        case serif = 2
        case script = 3
        case condensed = 4
    }
    public let textStyle: TextStyle

    private let textForegroundColorHex: UInt?
    public var textForegroundColor: UIColor? { textForegroundColorHex.map { UIColor(rgbHex: $0) } }

    private let textBackgroundColorHex: UInt?
    public var textBackgroundColor: UIColor? { textBackgroundColorHex.map { UIColor(rgbHex: $0) } }

    private enum RawBackground: Codable {
        case color(hex: UInt)
        case gradient(raw: RawGradient)
        struct RawGradient: Codable {
            let startColorHex: UInt
            let endColorHex: UInt
            let angle: UInt32
        }
    }
    private let rawBackground: RawBackground

    public enum Background {
        case color(UIColor)
        case gradient(Gradient)
        public struct Gradient {
            let startColor: UIColor
            let endColor: UIColor
            let angle: UInt32
        }
    }
    public var background: Background {
        switch rawBackground {
        case .color(let hex):
            return .color(.init(rgbHex: hex))
        case .gradient(let rawGradient):
            return .gradient(.init(
                startColor: .init(rgbHex: rawGradient.startColorHex),
                endColor: .init(rgbHex: rawGradient.endColorHex),
                angle: rawGradient.angle
            ))
        }
    }

    public private(set) var preview: OWSLinkPreview?

    init(from proto: SSKProtoTextAttachment, transaction: SDSAnyWriteTransaction) throws {
        guard let text = proto.text?.nilIfEmpty else {
            throw OWSAssertionError("Missing text for attachment.")
        }
        self.text = text

        guard let style = proto.textStyle else {
            throw OWSAssertionError("Missing style for attachment.")
        }

        switch style {
        case .default, .regular:
            self.textStyle = .regular
        case .bold:
            self.textStyle = .bold
        case .serif:
            self.textStyle = .serif
        case .script:
            self.textStyle = .script
        case .condensed:
            self.textStyle = .condensed
        }

        if proto.hasTextForegroundColor {
            textForegroundColorHex = UInt(proto.textForegroundColor)
        } else {
            textForegroundColorHex = nil
        }

        if proto.hasTextBackgroundColor {
            textBackgroundColorHex = UInt(proto.textBackgroundColor)
        } else {
            textBackgroundColorHex = nil
        }

        if let gradient = proto.gradient {
            rawBackground = .gradient(raw: .init(
                startColorHex: UInt(gradient.startColor),
                endColorHex: UInt(gradient.endColor),
                angle: gradient.angle
            ))
        } else if proto.hasColor {
            rawBackground = .color(hex: UInt(proto.color))
        } else {
            throw OWSAssertionError("Missing background for attachment.")
        }

        if let preview = proto.preview {
            self.preview = try OWSLinkPreview.buildValidatedLinkPreview(proto: preview, transaction: transaction)
        }
    }
}
