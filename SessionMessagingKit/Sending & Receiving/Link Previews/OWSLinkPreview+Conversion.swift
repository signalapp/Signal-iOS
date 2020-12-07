
extension OWSLinkPreview {
    
    @objc public static func from(_ linkPreview: VisibleMessage.LinkPreview?) -> OWSLinkPreview? {
        guard let linkPreview = linkPreview else { return nil }
        return OWSLinkPreview(urlString: linkPreview.url!, title: linkPreview.title, imageAttachmentId: linkPreview.attachmentID)
    }
}

extension VisibleMessage.LinkPreview {

    public static func from(_ linkPreview: OWSLinkPreview?) -> VisibleMessage.LinkPreview? {
        guard let linkPreview = linkPreview else { return nil }
        return VisibleMessage.LinkPreview(title: linkPreview.title, url: linkPreview.urlString!, attachmentID: linkPreview.imageAttachmentId)
    }
    
    @objc(from:using:)
    public static func from(_ linkPreview: OWSLinkPreviewDraft?, using transaction: YapDatabaseReadWriteTransaction) -> VisibleMessage.LinkPreview? {
        guard let linkPreview = linkPreview else { return nil }
        do {
            let linkPreview = try OWSLinkPreview.buildValidatedLinkPreview(fromInfo: linkPreview, transaction: transaction)
            return VisibleMessage.LinkPreview(title: linkPreview.title, url: linkPreview.urlString!, attachmentID: linkPreview.imageAttachmentId)
        } catch {
            return nil
        }
    }
}
