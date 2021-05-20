
public extension Message {

    enum Destination {
        case contact(publicKey: String)
        case closedGroup(groupPublicKey: String)
        case openGroup(channel: UInt64, server: String)
        case openGroupV2(room: String, server: String)

        static func from(_ thread: TSThread) -> Message.Destination {
            if let thread = thread as? TSContactThread {
                return .contact(publicKey: thread.contactSessionID())
            } else if let thread = thread as? TSGroupThread, thread.isClosedGroup {
                let groupID = thread.groupModel.groupId
                let groupPublicKey = LKGroupUtilities.getDecodedGroupID(groupID)
                return .closedGroup(groupPublicKey: groupPublicKey)
            } else if let thread = thread as? TSGroupThread, thread.isOpenGroup {
                let openGroupV2 = Storage.shared.getV2OpenGroup(for: thread.uniqueId!)!
                return .openGroupV2(room: openGroupV2.room, server: openGroupV2.server)
            } else {
                preconditionFailure("TODO: Handle legacy closed groups.")
            }
        }
    }
}
