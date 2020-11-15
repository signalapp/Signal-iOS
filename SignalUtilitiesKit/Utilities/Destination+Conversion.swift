
public extension Message.Destination {

    static func from(_ thread: TSThread) -> Message.Destination {
        if let thread = thread as? TSContactThread {
            return .contact(publicKey: thread.uniqueId!)
        } else if let thread = thread as? TSGroupThread, thread.usesSharedSenderKeys {
            let groupID = thread.groupModel.groupId
            let groupPublicKey = LKGroupUtilities.getDecodedGroupID(groupID)
            return .closedGroup(groupPublicKey: groupPublicKey)
        } else if let thread = thread as? TSGroupThread, thread.isOpenGroup {
            var openGroup: OpenGroup!
            Storage.read { transaction in
                openGroup = LokiDatabaseUtilities.getPublicChat(for: thread.uniqueId!, in: transaction)
            }
            return .openGroup(channel: openGroup.channel, server: openGroup.server)
        } else {
            preconditionFailure("TODO: Handle legacy closed groups.")
        }
    }
}
