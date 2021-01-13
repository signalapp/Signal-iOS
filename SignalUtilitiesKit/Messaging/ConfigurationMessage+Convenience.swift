
extension ConfigurationMessage {

    public static func getCurrent() -> ConfigurationMessage {
        var closedGroups: Set<ClosedGroup> = []
        var openGroups: Set<String> = []
        Storage.read { transaction in
            TSGroupThread.enumerateCollectionObjects(with: transaction) { object, _ in
                guard let thread = object as? TSGroupThread else { return }
                switch thread.groupModel.groupType {
                case .closedGroup:
                    guard thread.isCurrentUserMemberInGroup() else { return }
                    let groupID = thread.groupModel.groupId
                    let groupPublicKey = LKGroupUtilities.getDecodedGroupID(groupID)
                    guard Storage.shared.isClosedGroup(groupPublicKey),
                        let encryptionKeyPair = Storage.shared.getLatestClosedGroupEncryptionKeyPair(for: groupPublicKey) else { return }
                    let closedGroup = ClosedGroup(publicKey: groupPublicKey, name: thread.groupModel.groupName!, encryptionKeyPair: encryptionKeyPair,
                        members: Set(thread.groupModel.groupMemberIds), admins: Set(thread.groupModel.groupAdminIds))
                    closedGroups.insert(closedGroup)
                case .openGroup:
                    guard let openGroup = Storage.shared.getOpenGroup(for: thread.uniqueId!) else { return }
                    openGroups.insert(openGroup.server)
                default: break
                }
            }
        }
        return ConfigurationMessage(closedGroups: closedGroups, openGroups: openGroups)
    }
}
