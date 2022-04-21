// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

@objc(SNVisibleMessage)
public final class VisibleMessage: Message {
    private enum CodingKeys: String, CodingKey {
        case syncTarget
        case text = "body"
        case attachmentIDs = "attachments"
        case quote
        case linkPreview
        case profile
        case openGroupInvitation
    }
    
    /// In the case of a sync message, the public key of the person the message was targeted at.
    ///
    /// - Note: `nil` if this isn't a sync message.
    public var syncTarget: String?
    @objc public var text: String?
    @objc public var attachmentIDs: [String] = []
    @objc public var quote: Quote?
    @objc public var linkPreview: LinkPreview?
    @objc public var contact: Legacy.Contact?
    @objc public var profile: Profile?
    @objc public var openGroupInvitation: OpenGroupInvitation?

    public override var isSelfSendValid: Bool { true }
    
    // MARK: Initialization
    public override init() { super.init() }

    // MARK: Validation
    public override var isValid: Bool {
        guard super.isValid else { return false }
        if !attachmentIDs.isEmpty { return true }
        if openGroupInvitation != nil { return true }
        if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return true }
        return false
    }

    // MARK: Coding
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        if let syncTarget = coder.decodeObject(forKey: "syncTarget") as! String? { self.syncTarget = syncTarget }
        if let text = coder.decodeObject(forKey: "body") as! String? { self.text = text }
        if let attachmentIDs = coder.decodeObject(forKey: "attachments") as! [String]? { self.attachmentIDs = attachmentIDs }
        if let quote = coder.decodeObject(forKey: "quote") as! Quote? { self.quote = quote }
        if let linkPreview = coder.decodeObject(forKey: "linkPreview") as! LinkPreview? { self.linkPreview = linkPreview }
        if let profile = coder.decodeObject(forKey: "profile") as! Profile? { self.profile = profile }
        if let openGroupInvitation = coder.decodeObject(forKey: "openGroupInvitation") as! OpenGroupInvitation? { self.openGroupInvitation = openGroupInvitation }
    }
    
    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(syncTarget, forKey: "syncTarget")
        coder.encode(text, forKey: "body")
        coder.encode(attachmentIDs, forKey: "attachments")
        coder.encode(quote, forKey: "quote")
        coder.encode(linkPreview, forKey: "linkPreview")
        coder.encode(profile, forKey: "profile")
        coder.encode(openGroupInvitation, forKey: "openGroupInvitation")
    }
    
    // MARK: - Codable
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        
        syncTarget = try? container.decode(String.self, forKey: .syncTarget)
        text = try? container.decode(String.self, forKey: .text)
        attachmentIDs = ((try? container.decode([String].self, forKey: .attachmentIDs)) ?? [])
        quote = try? container.decode(Quote.self, forKey: .quote)
        linkPreview = try? container.decode(LinkPreview.self, forKey: .linkPreview)
        profile = try? container.decode(Profile.self, forKey: .profile)
        openGroupInvitation = try? container.decode(OpenGroupInvitation.self, forKey: .openGroupInvitation)
    }
    
    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encodeIfPresent(syncTarget, forKey: .syncTarget)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(attachmentIDs, forKey: .attachmentIDs)
        try container.encodeIfPresent(quote, forKey: .quote)
        try container.encodeIfPresent(linkPreview, forKey: .linkPreview)
        try container.encodeIfPresent(profile, forKey: .profile)
        try container.encodeIfPresent(openGroupInvitation, forKey: .openGroupInvitation)
    }

    // MARK: Proto Conversion
    public override class func fromProto(_ proto: SNProtoContent, sender: String) -> VisibleMessage? {
        guard let dataMessage = proto.dataMessage else { return nil }
        let result = VisibleMessage()
        result.text = dataMessage.body
        // Attachments are handled in MessageReceiver
        if let quoteProto = dataMessage.quote, let quote = Quote.fromProto(quoteProto) { result.quote = quote }
        if let linkPreviewProto = dataMessage.preview.first, let linkPreview = LinkPreview.fromProto(linkPreviewProto) { result.linkPreview = linkPreview }
        // TODO: Contact
        if let profile = Profile.fromProto(dataMessage) { result.profile = profile }
        if let openGroupInvitationProto = dataMessage.openGroupInvitation,
            let openGroupInvitation = OpenGroupInvitation.fromProto(openGroupInvitationProto) { result.openGroupInvitation = openGroupInvitation }
        result.syncTarget = dataMessage.syncTarget
        return result
    }

    public override func toProto(_ db: Database) -> SNProtoContent? {
        let proto = SNProtoContent.builder()
        var attachmentIDs = self.attachmentIDs
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
        
        if let quotedAttachmentID = quote?.attachmentID, let index = attachmentIDs.firstIndex(of: quotedAttachmentID) {
            attachmentIDs.remove(at: index)
        }
        
        if let quote = quote, let quoteProto = quote.toProto(db) {
            dataMessage.setQuote(quoteProto)
        }
        
        // Link preview
        if let linkPreviewAttachmentID = linkPreview?.attachmentID, let index = attachmentIDs.firstIndex(of: linkPreviewAttachmentID) {
            attachmentIDs.remove(at: index)
        }
        
        if let linkPreview = linkPreview, let linkPreviewProto = linkPreview.toProto(db) {
            dataMessage.setPreview([ linkPreviewProto ])
        }
        
        // Attachments
        
        let attachments: [SessionMessagingKit.Attachment]? = try? SessionMessagingKit.Attachment.fetchAll(db, ids: self.attachmentIDs)
        
        if !(attachments ?? []).allSatisfy({ $0.state == .uploaded }) {
            #if DEBUG
            preconditionFailure("Sending a message before all associated attachments have been uploaded.")
            #endif
        }
        let attachmentProtos = (attachments ?? []).compactMap { $0.buildProto() }
        dataMessage.setAttachments(attachmentProtos)
        
        // TODO: Contact
        
        // Open group invitation
        if let openGroupInvitation = openGroupInvitation, let openGroupInvitationProto = openGroupInvitation.toProto() { dataMessage.setOpenGroupInvitation(openGroupInvitationProto) }
        
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
    
    // MARK: Description
    public override var description: String {
        """
        VisibleMessage(
            text: \(text ?? "null"),
            attachmentIDs: \(attachmentIDs),
            quote: \(quote?.description ?? "null"),
            linkPreview: \(linkPreview?.description ?? "null"),
            contact: \(contact?.description ?? "null"),
            profile: \(profile?.description ?? "null")
            "openGroupInvitation": \(openGroupInvitation?.description ?? "null")
        )
        """
    }
}

// MARK: - Database Type Conversion

public extension VisibleMessage {
    static func from(_ db: Database, interaction: Interaction) -> VisibleMessage {
        let result = VisibleMessage()
        result.sentTimestamp = UInt64(interaction.timestampMs)
        result.recipient = (try? interaction.recipientStates.fetchOne(db))?.recipientId
        
        if let thread: SessionThread = try? interaction.thread.fetchOne(db), thread.variant == .closedGroup {
            result.groupPublicKey = thread.id
        }
        
        result.text = interaction.body
        result.attachmentIDs = ((try? interaction.attachments.fetchAll(db)) ?? []).map { $0.id }
        result.quote = (try? interaction.quote.fetchOne(db))
            .map { VisibleMessage.Quote.from(db, quote: $0) }
        
        if let linkPreview: SessionMessagingKit.LinkPreview = try? interaction.linkPreview.fetchOne(db) {
            switch linkPreview.variant {
                case .standard:
                    result.linkPreview = VisibleMessage.LinkPreview.from(db, linkPreview: linkPreview)
                    
                case .openGroupInvitation:
                    result.openGroupInvitation = VisibleMessage.OpenGroupInvitation.from(
                        db,
                        linkPreview: linkPreview
                    )
            }
        }
        
        return result
    }
}
