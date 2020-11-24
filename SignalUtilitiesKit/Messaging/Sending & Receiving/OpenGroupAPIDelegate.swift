
public final class OpenGroupAPIDelegate : SessionMessagingKit.OpenGroupAPIDelegate {
    
    public static let shared = OpenGroupAPIDelegate()
    
    public func updateProfileIfNeeded(for channel: UInt64, on server: String, from info: OpenGroupInfo) {
        let openGroupID = "\(server).\(channel)"
        Storage.write { transaction in
            // Update user count
            Storage.shared.setUserCount(to: info.memberCount, forOpenGroupWithID: openGroupID, using: transaction)
            let thread = TSGroupThread.getOrCreateThread(withGroupId: openGroupID.data(using: .utf8)!, groupType: .openGroup, transaction: transaction)
            // Update display name if needed
            let model = thread.groupModel
            if model.groupName != info.displayName {
                let newGroupModel = TSGroupModel(title: info.displayName, memberIds: model.groupMemberIds, image: model.groupImage, groupId: model.groupId, groupType: model.groupType, adminIds: model.groupAdminIds)
                thread.groupModel = newGroupModel
                thread.save(with: transaction)
            }
            // Download and update profile picture if needed
            let oldProfilePictureURL = Storage.shared.getProfilePictureURL(forOpenGroupWithID: openGroupID)
            if oldProfilePictureURL != info.profilePictureURL || model.groupImage == nil {
                Storage.shared.setProfilePictureURL(to: info.profilePictureURL, forOpenGroupWithID: openGroupID, using: transaction)
                if let profilePictureURL = info.profilePictureURL {
                    var sanitizedServerURL = server
                    while sanitizedServerURL.hasSuffix("/") { sanitizedServerURL.removeLast() }
                    var sanitizedProfilePictureURL = profilePictureURL
                    while sanitizedProfilePictureURL.hasPrefix("/") { sanitizedProfilePictureURL.removeFirst() }
                    let url = "\(sanitizedServerURL)/\(sanitizedProfilePictureURL)"
                    FileServerAPI.downloadAttachment(from: url).map2 { data in
                        let attachmentStream = TSAttachmentStream(contentType: OWSMimeTypeImageJpeg, byteCount: UInt32(data.count), sourceFilename: nil, caption: nil, albumMessageId: nil)
                        try attachmentStream.write(data)
                        thread.updateAvatar(with: attachmentStream)
                    }
                }
            }
        }
    }
}
