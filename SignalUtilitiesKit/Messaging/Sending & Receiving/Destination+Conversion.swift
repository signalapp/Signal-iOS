
public extension Message.Destination {

    static func from(_ thread: TSThread) -> Message.Destination {
        if let thread = thread as? TSContactThread {
            return .contact(publicKey: thread.contactIdentifier())
        } else if let thread = thread as? TSGroupThread, thread.usesSharedSenderKeys {
            let groupID = thread.groupModel.groupId
            let groupPublicKey = LKGroupUtilities.getDecodedGroupID(groupID)
            return .closedGroup(groupPublicKey: groupPublicKey)
        } else if let thread = thread as? TSGroupThread, thread.isOpenGroup {
            let openGroup = Storage.shared.getOpenGroup(for: thread.uniqueId!)!
            return .openGroup(channel: openGroup.channel, server: openGroup.server)
        } else {
            preconditionFailure("TODO: Handle legacy closed groups.")
        }
    }
}
