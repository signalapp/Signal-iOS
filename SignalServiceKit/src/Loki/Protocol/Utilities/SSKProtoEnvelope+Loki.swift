
@objc public extension SSKProtoEnvelope {
    
    @objc public var isGroupChatMessage: Bool {
        do {
            let contentProto = try SSKProtoContent.parseData(content!)
            return contentProto.dataMessage?.group != nil
        } catch {
            return false
        }
    }
}
