
extension ConfigurationMessage {

    public static func getCurrent() -> ConfigurationMessage {
        let storage = Storage.shared
        let displayName = storage.getUserDisplayName()!
        let profilePictureURL = SSKEnvironment.shared.profileManager.profilePictureURL()
        let profileKey = storage.getUserProfileKey()
        var closedGroups: Set<ClosedGroup> = []
        var openGroups: Set<String> = []
        var contacts: Set<Contact> = []
        var contactCount = 0
        Storage.read { transaction in
            TSGroupThread.enumerateCollectionObjects(with: transaction) { object, _ in
                guard let thread = object as? TSGroupThread else { return }
                switch thread.groupModel.groupType {
                case .closedGroup:
                    guard thread.isCurrentUserMemberInGroup() else { return }
                    let groupID = thread.groupModel.groupId
                    let groupPublicKey = LKGroupUtilities.getDecodedGroupID(groupID)
                    guard storage.isClosedGroup(groupPublicKey),
                        let encryptionKeyPair = storage.getLatestClosedGroupEncryptionKeyPair(for: groupPublicKey) else { return }
                    let closedGroup = ClosedGroup(publicKey: groupPublicKey, name: thread.groupModel.groupName!, encryptionKeyPair: encryptionKeyPair,
                        members: Set(thread.groupModel.groupMemberIds), admins: Set(thread.groupModel.groupAdminIds))
                    closedGroups.insert(closedGroup)
                case .openGroup:
                    guard let openGroup = storage.getOpenGroup(for: thread.uniqueId!) else { return }
                    openGroups.insert(openGroup.server)
                default: break
                }
            }
            OWSUserProfile.enumerateCollectionObjects(with: transaction) { object, stop in
                guard let profile = object as? OWSUserProfile, let displayName = profile.profileName else { return }
                let publicKey = profile.recipientId
                let profilePictureURL = profile.avatarUrlPath
                let profileKey = profile.profileKey?.keyData
                let contact = ConfigurationMessage.Contact(publicKey: publicKey, displayName: displayName,
                    profilePictureURL: profilePictureURL, profileKey: profileKey)
                contacts.insert(contact)
                guard contactCount < 200 else { stop.pointee = true; return }
                contactCount += 1
            }
        }
        return ConfigurationMessage(displayName: displayName, profilePictureURL: profilePictureURL, profileKey: profileKey,
            closedGroups: closedGroups, openGroups: openGroups, contacts: contacts)
    }
}
