
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
            fileIds: [Int64]? = nil // TODO: Handle 'fileIds'
        )

        static func from(_ thread: TSThread) -> Message.Destination {
            if let thread = thread as? TSContactThread {
                return .contact(publicKey: thread.contactSessionID())
            }
            
            if let thread = thread as? TSGroupThread, thread.isClosedGroup {
                let groupID = thread.groupModel.groupId
                let groupPublicKey = LKGroupUtilities.getDecodedGroupID(groupID)
                return .closedGroup(groupPublicKey: groupPublicKey)
            }
            
            if let thread = thread as? TSGroupThread, thread.isOpenGroup {
                let openGroup: OpenGroupV2 = Storage.shared.getV2OpenGroup(for: thread.uniqueId!)!
                
                return .openGroup(roomToken: openGroup.room, server: openGroup.server)
            }
            
            preconditionFailure("TODO: Handle legacy closed groups.")
        }
    }
}
