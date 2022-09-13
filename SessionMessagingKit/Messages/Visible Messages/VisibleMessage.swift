// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public final class VisibleMessage: Message {
    private enum CodingKeys: String, CodingKey {
        case syncTarget
        case text = "body"
        case attachmentIds = "attachments"
        case quote
        case linkPreview
        case profile
        case openGroupInvitation
        case reaction
    }
    
    /// In the case of a sync message, the public key of the person the message was targeted at.
    ///
    /// - Note: `nil` if this isn't a sync message.
    public var syncTarget: String?
    public let text: String?
    public var attachmentIds: [String]
    public let quote: VMQuote?
    public let linkPreview: VMLinkPreview?
    public var profile: VMProfile?
    public let openGroupInvitation: VMOpenGroupInvitation?
    public let reaction: VMReaction?

    public override var isSelfSendValid: Bool { true }
    
    // MARK: - Validation
    
    public override var isValid: Bool {
        guard super.isValid else { return false }
        if !attachmentIds.isEmpty { return true }
        if openGroupInvitation != nil { return true }
        if reaction != nil { return true }
        if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return true }
        return false
    }
    
    // MARK: - Initialization
    
    public init(
        sentTimestamp: UInt64? = nil,
        recipient: String? = nil,
        groupPublicKey: String? = nil,
        syncTarget: String? = nil,
        text: String?,
        attachmentIds: [String] = [],
        quote: VMQuote? = nil,
        linkPreview: VMLinkPreview? = nil,
        profile: VMProfile? = nil,
        openGroupInvitation: VMOpenGroupInvitation? = nil,
        reaction: VMReaction? = nil
    ) {
        self.syncTarget = syncTarget
        self.text = text
        self.attachmentIds = attachmentIds
        self.quote = quote
        self.linkPreview = linkPreview
        self.profile = profile
        self.openGroupInvitation = openGroupInvitation
        self.reaction = reaction
        
        super.init(
            sentTimestamp: sentTimestamp,
            recipient: recipient,
            groupPublicKey: groupPublicKey
        )
    }
    
    // MARK: - Codable
    
    required init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        
        syncTarget = try? container.decode(String.self, forKey: .syncTarget)
        text = try? container.decode(String.self, forKey: .text)
        attachmentIds = ((try? container.decode([String].self, forKey: .attachmentIds)) ?? [])
        quote = try? container.decode(VMQuote.self, forKey: .quote)
        linkPreview = try? container.decode(VMLinkPreview.self, forKey: .linkPreview)
        profile = try? container.decode(VMProfile.self, forKey: .profile)
        openGroupInvitation = try? container.decode(VMOpenGroupInvitation.self, forKey: .openGroupInvitation)
        reaction = try? container.decode(VMReaction.self, forKey: .reaction)
        
        try super.init(from: decoder)
    }
    
    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encodeIfPresent(syncTarget, forKey: .syncTarget)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(attachmentIds, forKey: .attachmentIds)
        try container.encodeIfPresent(quote, forKey: .quote)
        try container.encodeIfPresent(linkPreview, forKey: .linkPreview)
        try container.encodeIfPresent(profile, forKey: .profile)
        try container.encodeIfPresent(openGroupInvitation, forKey: .openGroupInvitation)
        try container.encodeIfPresent(reaction, forKey: .reaction)
    }

    // MARK: - Proto Conversion
    
    public override class func fromProto(_ proto: SNProtoContent, sender: String) -> VisibleMessage? {
        guard let dataMessage = proto.dataMessage else { return nil }
        
        return VisibleMessage(
            syncTarget: dataMessage.syncTarget,
            text: dataMessage.body,
            attachmentIds: [],    // Attachments are handled in MessageReceiver
            quote: dataMessage.quote.map { VMQuote.fromProto($0) },
            linkPreview: dataMessage.preview.first.map { VMLinkPreview.fromProto($0) },
            profile: VMProfile.fromProto(dataMessage),
            openGroupInvitation: dataMessage.openGroupInvitation.map { VMOpenGroupInvitation.fromProto($0) },
            reaction: dataMessage.reaction.map { VMReaction.fromProto($0) }
        )
    }

    public override func toProto(_ db: Database) -> SNProtoContent? {
        let proto = SNProtoContent.builder()
        var attachmentIds = self.attachmentIds
        let dataMessage: SNProtoDataMessage.SNProtoDataMessageBuilder
        
        // Profile
        if let profile = profile, let profileProto = profile.toProto() {
            dataMessage = profileProto.asBuilder()
        }
        else {
            dataMessage = SNProtoDataMessage.builder()
        }
        
        // Text
        if let text = text { dataMessage.setBody(text) }
        
        // Quote
        
        if let quotedAttachmentId = quote?.attachmentId, let index = attachmentIds.firstIndex(of: quotedAttachmentId) {
            attachmentIds.remove(at: index)
        }
        
        if let quote = quote, let quoteProto = quote.toProto(db) {
            dataMessage.setQuote(quoteProto)
        }
        
        // Link preview
        if let linkPreviewAttachmentId = linkPreview?.attachmentId, let index = attachmentIds.firstIndex(of: linkPreviewAttachmentId) {
            attachmentIds.remove(at: index)
        }
        
        if let linkPreview = linkPreview, let linkPreviewProto = linkPreview.toProto(db) {
            dataMessage.setPreview([ linkPreviewProto ])
        }
        
        // Attachments
        
        let attachments: [Attachment]? = try? Attachment.fetchAll(db, ids: self.attachmentIds)
        
        if !(attachments ?? []).allSatisfy({ $0.state == .uploaded }) {
            #if DEBUG
            preconditionFailure("Sending a message before all associated attachments have been uploaded.")
            #endif
        }
        let attachmentProtos = (attachments ?? []).compactMap { $0.buildProto() }
        dataMessage.setAttachments(attachmentProtos)
        
        // Open group invitation
        if
            let openGroupInvitation = openGroupInvitation,
            let openGroupInvitationProto = openGroupInvitation.toProto()
        {
            dataMessage.setOpenGroupInvitation(openGroupInvitationProto)
        }
        
        // Emoji react
        if let reaction = reaction, let reactionProto = reaction.toProto() {
            dataMessage.setReaction(reactionProto)
        }
        
        // Group context
        do {
            try setGroupContextIfNeeded(db, on: dataMessage)
        } catch {
            SNLog("Couldn't construct visible message proto from: \(self).")
            return nil
        }
        
        // Sync target
        if let syncTarget = syncTarget {
            dataMessage.setSyncTarget(syncTarget)
        }
        
        // Build
        do {
            proto.setDataMessage(try dataMessage.build())
            return try proto.build()
        } catch {
            SNLog("Couldn't construct visible message proto from: \(self).")
            return nil
        }
    }
    
    // MARK: - Description
    
    public var description: String {
        """
        VisibleMessage(
            text: \(text ?? "null"),
            attachmentIds: \(attachmentIds),
            quote: \(quote?.description ?? "null"),
            linkPreview: \(linkPreview?.description ?? "null"),
            profile: \(profile?.description ?? "null"),
            reaction: \(reaction?.description ?? "null"),
            openGroupInvitation: \(openGroupInvitation?.description ?? "null")
        )
        """
    }
}

// MARK: - Database Type Conversion

public extension VisibleMessage {
    static func from(_ db: Database, interaction: Interaction) -> VisibleMessage {
        let linkPreview: LinkPreview? = try? interaction.linkPreview.fetchOne(db)
        
        return VisibleMessage(
            sentTimestamp: UInt64(interaction.timestampMs),
            recipient: (try? interaction.recipientStates.fetchOne(db))?.recipientId,
            groupPublicKey: try? interaction.thread
                .filter(SessionThread.Columns.variant == SessionThread.Variant.closedGroup)
                .select(.id)
                .asRequest(of: String.self)
                .fetchOne(db),
            syncTarget: nil,
            text: interaction.body,
            attachmentIds: ((try? interaction.attachments.fetchAll(db)) ?? [])
                .map { $0.id },
            quote: (try? interaction.quote.fetchOne(db))
                .map { VMQuote.from(db, quote: $0) },
            linkPreview: linkPreview
                .map { linkPreview in
                    guard linkPreview.variant == .standard else { return nil }
                    
                    return VMLinkPreview.from(db, linkPreview: linkPreview)
                },
            profile: nil,   // Don't attach the profile to avoid sending a legacy version (set in MessageSender)
            openGroupInvitation: linkPreview.map { linkPreview in
                guard linkPreview.variant == .openGroupInvitation else { return nil }
                
                return VMOpenGroupInvitation.from(
                    db,
                    linkPreview: linkPreview
                )
            },
            reaction: nil   // Reactions are custom messages sent separately
        )
    }
}
