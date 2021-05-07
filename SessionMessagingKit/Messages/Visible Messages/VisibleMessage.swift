import SessionUtilitiesKit

@objc(SNVisibleMessage)
public final class VisibleMessage : Message {
    /// In the case of a sync message, the public key of the person the message was targeted at.
    ///
    /// - Note: `nil` if this isn't a sync message.
    public var syncTarget: String?
    @objc public var text: String?
    @objc public var attachmentIDs: [String] = []
    @objc public var quote: Quote?
    @objc public var linkPreview: LinkPreview?
    @objc public var contact: Contact?
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
        // TODO: Contact
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
        // TODO: Contact
        coder.encode(profile, forKey: "profile")
        coder.encode(openGroupInvitation, forKey: "openGroupInvitation")
    }

    // MARK: Proto Conversion
    public override class func fromProto(_ proto: SNProtoContent) -> VisibleMessage? {
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

    public override func toProto(using transaction: YapDatabaseReadWriteTransaction) -> SNProtoContent? {
        let proto = SNProtoContent.builder()
        var attachmentIDs = self.attachmentIDs
        let dataMessage: SNProtoDataMessage.SNProtoDataMessageBuilder
        // Profile
        if let profile = profile, let profileProto = profile.toProto() {
            dataMessage = profileProto.asBuilder()
        } else {
            dataMessage = SNProtoDataMessage.builder()
        }
        // Text
        if let text = text { dataMessage.setBody(text) }
        // Quote
        if let quotedAttachmentID = quote?.attachmentID, let index = attachmentIDs.firstIndex(of: quotedAttachmentID) {
            attachmentIDs.remove(at: index)
        }
        if let quote = quote, let quoteProto = quote.toProto(using: transaction) { dataMessage.setQuote(quoteProto) }
        // Link preview
        if let linkPreviewAttachmentID = linkPreview?.attachmentID, let index = attachmentIDs.firstIndex(of: linkPreviewAttachmentID) {
            attachmentIDs.remove(at: index)
        }
        if let linkPreview = linkPreview, let linkPreviewProto = linkPreview.toProto(using: transaction) { dataMessage.setPreview([ linkPreviewProto ]) }
        // Attachments
        let attachments = attachmentIDs.compactMap { TSAttachment.fetch(uniqueId: $0, transaction: transaction) as? TSAttachmentStream }
        if !attachments.allSatisfy({ $0.isUploaded }) {
            #if DEBUG
            preconditionFailure("Sending a message before all associated attachments have been uploaded.")
            #endif
        }
        let attachmentProtos = attachments.compactMap { $0.buildProto() }
        dataMessage.setAttachments(attachmentProtos)
        // TODO: Contact
        // Open group invitation
        if let openGroupInvitation = openGroupInvitation, let openGroupInvitationProto = openGroupInvitation.toProto() { dataMessage.setOpenGroupInvitation(openGroupInvitationProto) }
        // Expiration timer
        // TODO: We * want * expiration timer updates to be explicit. But currently Android will disable the expiration timer for a conversation
        // if it receives a message without the current expiration timer value attached to it...
        var expiration: UInt32 = 0
        if let disappearingMessagesConfiguration = OWSDisappearingMessagesConfiguration.fetch(uniqueId: threadID!, transaction: transaction) {
            expiration = disappearingMessagesConfiguration.isEnabled ? disappearingMessagesConfiguration.durationSeconds : 0
        }
        dataMessage.setExpireTimer(expiration)
        // Group context
        do {
            try setGroupContextIfNeeded(on: dataMessage, using: transaction)
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
