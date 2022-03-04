
public extension Message {

    enum Destination {
        case contact(publicKey: String)
        case closedGroup(groupPublicKey: String)
        case legacyOpenGroup(channel: UInt64, server: String)
        case openGroup(
            roomToken: String,
            server: String,
            whisperTo: String? = nil,
            whisperMods: Bool = false,
            fileIds: [UInt64]? = nil
        )
        case openGroupInbox(server: String, openGroupPublicKey: String, blindedPublicKey: String)

        static func from(_ thread: TSThread, fileIds: [UInt64]? = nil) -> Message.Destination {
            if let thread = thread as? TSContactThread {
                if SessionId.Prefix(from: thread.contactSessionID()) == .blinded {
                    guard let server: String = thread.originalOpenGroupServer, let publicKey: String = thread.originalOpenGroupPublicKey else {
                        preconditionFailure("Attempting to send message to blinded id without the Open Group information")
                    }
                    
                    return .openGroupInbox(
                        server: server,
                        openGroupPublicKey: publicKey,
                        blindedPublicKey: thread.contactSessionID()
                    )
                }
                
                return .contact(publicKey: thread.contactSessionID())
            }
            
            if let thread = thread as? TSGroupThread, thread.isClosedGroup {
                let groupID = thread.groupModel.groupId
                let groupPublicKey = LKGroupUtilities.getDecodedGroupID(groupID)
                return .closedGroup(groupPublicKey: groupPublicKey)
            }
            
            if let thread = thread as? TSGroupThread, thread.isOpenGroup {
                let openGroup: OpenGroup = Storage.shared.getOpenGroup(for: thread.uniqueId!)!
                
                return .openGroup(roomToken: openGroup.room, server: openGroup.server, fileIds: fileIds)
            }
            
            preconditionFailure("TODO: Handle legacy closed groups.")
        }
    }
}
