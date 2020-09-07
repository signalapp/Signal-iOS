//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public class GroupInviteLinkViewModel: NSObject {
    @objc
    public let url: URL

    public let groupInviteLinkPreview: GroupInviteLinkPreview?

    public let avatar: GroupInviteLinkCachedAvatar?

    @objc
    public var isLoaded: Bool {
        groupInviteLinkPreview != nil
    }

    fileprivate init(url: URL,
                     groupInviteLinkPreview: GroupInviteLinkPreview?,
                     avatar: GroupInviteLinkCachedAvatar?) {
        self.url = url
        self.groupInviteLinkPreview = groupInviteLinkPreview
        self.avatar = avatar
    }

    @objc
    public override func isEqual(_ object: Any!) -> Bool {
        guard let other = object as? GroupInviteLinkViewModel else {
            return false
        }
        return (self.url == other.url &&
            self.groupInviteLinkPreview == other.groupInviteLinkPreview &&
            self.avatar == other.avatar)
    }
}

// MARK: -

@objc
public class GroupInviteLinkCachedAvatar: NSObject {
    let cacheFileUrl: URL
    let imageSizePixels: CGSize
    let isValid: Bool

    fileprivate init(cacheFileUrl: URL,
                     imageSizePixels: CGSize,
                     isValid: Bool) {
        self.cacheFileUrl = cacheFileUrl
        self.imageSizePixels = imageSizePixels
        self.isValid = isValid
    }

    @objc
    public override func isEqual(_ object: Any!) -> Bool {
        guard let other = object as? GroupInviteLinkCachedAvatar else {
            return false
        }
        return (self.cacheFileUrl == other.cacheFileUrl &&
            self.imageSizePixels == other.imageSizePixels &&
            self.isValid == other.isValid)
    }
}

// MARK: -

fileprivate extension ConversationInteractionViewItem {

    // MARK: - Dependencies

    private static var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private static var groupsV2: GroupsV2Swift {
        return SSKEnvironment.shared.groupsV2 as! GroupsV2Swift
    }

    // MARK: -

    private static let unfairLock = UnfairLock()
    private static var groupInviteLinkAvatarCache = [String: GroupInviteLinkCachedAvatar]()
    private static var groupInviteLinkAvatarsInFlight = Set<String>()

    private static func cachedGroupInviteLinkAvatar(avatarUrlPath: String) -> GroupInviteLinkCachedAvatar? {
        unfairLock.withLock {
            guard let cachedAvatar = groupInviteLinkAvatarCache[avatarUrlPath],
                cachedAvatar.isValid else {
                return nil
            }
            return cachedAvatar
        }
    }

    private static func loadGroupInviteLinkAvatar(avatarUrlPath: String,
                                                  groupInviteLinkInfo: GroupInviteLinkInfo) -> Promise<Void> {
        Self.unfairLock.withLock {
            guard !groupInviteLinkAvatarsInFlight.contains(avatarUrlPath) else {
                return
            }
            groupInviteLinkAvatarsInFlight.insert(avatarUrlPath)
        }

        return firstly(on: .global()) { () -> Promise<Data> in
            let groupV2ContextInfo = try Self.groupsV2.groupV2ContextInfo(forMasterKeyData: groupInviteLinkInfo.masterKey)
            return self.groupsV2.fetchGroupInviteLinkAvatar(avatarUrlPath: avatarUrlPath,
                                                            groupSecretParamsData: groupV2ContextInfo.groupSecretParamsData)
        }.map(on: .global()) { (avatarData: Data) -> Void in
            let imageMetadata = (avatarData as NSData).imageMetadata(withPath: nil, mimeType: nil)
            let cacheFileUrl = OWSFileSystem.temporaryFileUrl(fileExtension: imageMetadata.fileExtension,
                                                              isAvailableWhileDeviceLocked: true)
            guard imageMetadata.isValid else {
                let cachedAvatar = GroupInviteLinkCachedAvatar(cacheFileUrl: cacheFileUrl,
                                                               imageSizePixels: imageMetadata.pixelSize,
                                                               isValid: false)
                Self.unfairLock.withLock {
                    Self.groupInviteLinkAvatarCache[avatarUrlPath] = cachedAvatar
                    Self.groupInviteLinkAvatarsInFlight.remove(avatarUrlPath)
                }
                throw OWSAssertionError("Invalid group avatar.")
            }
            try avatarData.write(to: cacheFileUrl)
            let cachedAvatar = GroupInviteLinkCachedAvatar(cacheFileUrl: cacheFileUrl,
                                                           imageSizePixels: imageMetadata.pixelSize,
                                                           isValid: true)
            Self.unfairLock.withLock {
                Self.groupInviteLinkAvatarCache[avatarUrlPath] = cachedAvatar
                Self.groupInviteLinkAvatarsInFlight.remove(avatarUrlPath)
            }
        }.recover(on: .global()) { (error) -> Promise<Void> in
            _ = Self.unfairLock.withLock {
                Self.groupInviteLinkAvatarsInFlight.remove(avatarUrlPath)
            }
            throw error
        }
    }
}

// MARK: -

@objc
public extension ConversationInteractionViewItem {

    // MARK: - Notifications

    func configureGroupInviteLink(_ url: URL,
                                  message: TSMessage,
                                  groupInviteLinkInfo: GroupInviteLinkInfo) -> GroupInviteLinkViewModel {

        guard let groupInviteLinkPreview = GroupManager.cachedGroupInviteLinkPreview(groupInviteLinkInfo: groupInviteLinkInfo) else {
            // If there is no cached GroupInviteLinkPreview for this link,
            // try to do load it now. On success, touch the interaction
            // in order to trigger reload of the view.
            firstly(on: .global()) { () -> Promise<GroupInviteLinkPreview> in
                let groupContextInfo = try Self.groupsV2.groupV2ContextInfo(forMasterKeyData: groupInviteLinkInfo.masterKey)
                return Self.groupsV2.fetchGroupInviteLinkPreview(inviteLinkPassword: groupInviteLinkInfo.inviteLinkPassword,
                                                                 groupSecretParamsData: groupContextInfo.groupSecretParamsData,
                                                                 allowCached: false)
            }.done(on: .global()) { (_: GroupInviteLinkPreview) in
                Self.databaseStorage.write { transaction in
                    Self.databaseStorage.touch(interaction: message, transaction: transaction)
                }
            }.catch(on: .global()) { (error: Error) in
                // TODO: Add retry?
                owsFailDebug("Error: \(error)")
            }
            return GroupInviteLinkViewModel(url: url,
                                            groupInviteLinkPreview: nil,
                                            avatar: nil)
        }

        guard let avatarUrlPath = groupInviteLinkPreview.avatarUrlPath else {
            // If this group link has no avatar, there's nothing left to load.
            return GroupInviteLinkViewModel(url: url,
                                            groupInviteLinkPreview: groupInviteLinkPreview,
                                            avatar: nil)
        }

        guard let avatar = Self.cachedGroupInviteLinkAvatar(avatarUrlPath: avatarUrlPath) else {
            // If there is no cached avatar for this link,
            // try to do load it now. On success, touch the interaction
            // in order to trigger reload of the view.
            firstly(on: .global()) {
                Self.loadGroupInviteLinkAvatar(avatarUrlPath: avatarUrlPath,
                                               groupInviteLinkInfo: groupInviteLinkInfo)
            }.done(on: .global()) { () in
                Self.databaseStorage.write { transaction in
                    Self.databaseStorage.touch(interaction: message, transaction: transaction)
                }
            }.catch { error in
                // TODO: Add retry?
                if IsNetworkConnectivityFailure(error) {
                    Logger.warn("Error: \(error)")
                } else {
                    owsFailDebug("Error: \(error)")
                }
            }

            return GroupInviteLinkViewModel(url: url,
                                            groupInviteLinkPreview: groupInviteLinkPreview,
                                            avatar: nil)
        }

        return GroupInviteLinkViewModel(url: url,
                                        groupInviteLinkPreview: groupInviteLinkPreview,
                                        avatar: avatar)
    }
}
