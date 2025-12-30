//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

private extension CVComponentState {
    private struct GroupLinkState {
        var groupInviteLinkAvatarCache = [String: GroupInviteLinkCachedAvatar]()
        var expiredGroupInviteLinks = Set<URL>()
    }

    private static let groupLinkState = AtomicValue(GroupLinkState(), lock: .init())

    private static func updateExpirationList(url: URL, isExpired: Bool) -> Bool {
        return groupLinkState.update {
            if isExpired {
                return $0.expiredGroupInviteLinks.insert(url).inserted
            } else {
                return $0.expiredGroupInviteLinks.remove(url) != nil
            }
        }
    }

    private static func isGroupInviteLinkExpired(_ url: URL) -> Bool {
        return groupLinkState.update {
            return $0.expiredGroupInviteLinks.contains(url)
        }
    }

    private static func cachedGroupInviteLinkAvatar(avatarUrlPath: String) -> GroupInviteLinkCachedAvatar? {
        return groupLinkState.update {
            guard let cachedAvatar = $0.groupInviteLinkAvatarCache[avatarUrlPath], cachedAvatar.isValid else {
                return nil
            }
            return cachedAvatar
        }
    }

    private static func loadGroupInviteLinkAvatar(avatarUrlPath: String, groupInviteLinkInfo: GroupInviteLinkInfo) async throws {
        let contextInfo = try GroupV2ContextInfo.deriveFrom(masterKeyData: groupInviteLinkInfo.masterKey)
        let avatarData = try await SSKEnvironment.shared.groupsV2Ref.fetchGroupInviteLinkAvatar(
            avatarUrlPath: avatarUrlPath,
            groupSecretParams: contextInfo.groupSecretParams,
        )

        let imageMetadata = DataImageSource(avatarData).imageMetadata()
        guard let imageMetadata else {
            let cachedAvatar = GroupInviteLinkCachedAvatar(
                cacheFileUrl: OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true),
                imageSizePixels: .zero,
                isValid: false,
            )
            groupLinkState.update {
                $0.groupInviteLinkAvatarCache[avatarUrlPath] = cachedAvatar
            }
            throw OWSAssertionError("Invalid group avatar.")
        }
        let cacheFileUrl = OWSFileSystem.temporaryFileUrl(
            fileExtension: imageMetadata.imageFormat.fileExtension,
            isAvailableWhileDeviceLocked: true,
        )
        try avatarData.write(to: cacheFileUrl)
        let cachedAvatar = GroupInviteLinkCachedAvatar(
            cacheFileUrl: cacheFileUrl,
            imageSizePixels: imageMetadata.pixelSize,
            isValid: true,
        )
        groupLinkState.update {
            $0.groupInviteLinkAvatarCache[avatarUrlPath] = cachedAvatar
        }
    }
}

// MARK: -

extension CVComponentState {

    // MARK: - Notifications

    static func configureGroupInviteLink(
        _ url: URL,
        message: TSMessage,
        groupInviteLinkInfo: GroupInviteLinkInfo,
    ) -> GroupInviteLinkViewModel {

        let touchMessage = { () async -> Void in
            await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
                SSKEnvironment.shared.databaseStorageRef.touch(interaction: message, shouldReindex: false, tx: transaction)
            }
        }

        guard let groupInviteLinkPreview = GroupManager.cachedGroupInviteLinkPreview(groupInviteLinkInfo: groupInviteLinkInfo) else {
            // If there is no cached GroupInviteLinkPreview for this link,
            // try to do load it now. On success, touch the interaction
            // in order to trigger reload of the view.
            Task {
                do {
                    let groupContextInfo = try GroupV2ContextInfo.deriveFrom(masterKeyData: groupInviteLinkInfo.masterKey)
                    _ = try await SSKEnvironment.shared.groupsV2Ref.fetchGroupInviteLinkPreview(
                        inviteLinkPassword: groupInviteLinkInfo.inviteLinkPassword,
                        groupSecretParams: groupContextInfo.groupSecretParams,
                    )
                    _ = Self.updateExpirationList(url: url, isExpired: false)
                    await touchMessage()
                } catch {
                    switch error {
                    case GroupsV2Error.expiredGroupInviteLink, GroupsV2Error.localUserBlockedFromJoining:
                        Logger.warn("Failed to fetch group link content: \(error)")
                        if Self.updateExpirationList(url: url, isExpired: true) {
                            await touchMessage()
                        }
                    default:
                        // TODO: Add retry?
                        owsFailDebugUnlessNetworkFailure(error)
                    }
                }
            }
            return GroupInviteLinkViewModel(
                url: url,
                groupInviteLinkPreview: nil,
                avatar: nil,
                isExpired: Self.isGroupInviteLinkExpired(url),
            )
        }

        guard let avatarUrlPath = groupInviteLinkPreview.avatarUrlPath else {
            // If this group link has no avatar, there's nothing left to load.
            return GroupInviteLinkViewModel(
                url: url,
                groupInviteLinkPreview: groupInviteLinkPreview,
                avatar: nil,
                isExpired: false,
            )
        }

        guard let avatar = Self.cachedGroupInviteLinkAvatar(avatarUrlPath: avatarUrlPath) else {
            // If there is no cached avatar for this link, try to do load it now. On
            // success, touch the interaction in order to trigger reload of the view.
            Task {
                do {
                    try await Self.loadGroupInviteLinkAvatar(avatarUrlPath: avatarUrlPath, groupInviteLinkInfo: groupInviteLinkInfo)
                    await touchMessage()
                } catch {
                    // TODO: Add retry?
                    owsFailDebugUnlessNetworkFailure(error)
                }
            }

            return GroupInviteLinkViewModel(
                url: url,
                groupInviteLinkPreview: groupInviteLinkPreview,
                avatar: nil,
                isExpired: false,
            )
        }

        return GroupInviteLinkViewModel(
            url: url,
            groupInviteLinkPreview: groupInviteLinkPreview,
            avatar: avatar,
            isExpired: false,
        )
    }
}
