//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

private extension CVComponentState {
    private struct GroupLinkState {
        var groupInviteLinkAvatarCache = [String: GroupInviteLinkCachedAvatar]()
        var expiredGroupInviteLinks = Set<GroupInviteLink>()
    }

    private static let groupLinkState = AtomicValue(GroupLinkState(), lock: .init())

    private static func updateExpirationList(groupInviteLink: GroupInviteLink, isExpired: Bool) -> Bool {
        return groupLinkState.update {
            if isExpired {
                return $0.expiredGroupInviteLinks.insert(groupInviteLink).inserted
            } else {
                return $0.expiredGroupInviteLinks.remove(groupInviteLink) != nil
            }
        }
    }

    private static func isGroupInviteLinkExpired(groupInviteLink: GroupInviteLink) -> Bool {
        return groupLinkState.update {
            return $0.expiredGroupInviteLinks.contains(groupInviteLink)
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

    private static func loadGroupInviteLinkAvatar(avatarUrlPath: String, groupInviteLink: GroupInviteLink) async throws {
        let contextInfo = GroupV2ContextInfo.deriveFrom(masterKey: groupInviteLink.masterKey)
        let avatarData = try await SSKEnvironment.shared.groupsV2Ref.fetchGroupInviteLinkAvatar(
            avatarUrlPath: avatarUrlPath,
            groupSecretParams: contextInfo.groupSecretParams,
        )

        let imageMetadata = DataImageSource(avatarData).imageMetadata()
        guard let imageMetadata else {
            let cachedAvatar = GroupInviteLinkCachedAvatar(
                cacheFileUrl: OWSFileSystem.temporaryFileUrl(
                    fileExtension: nil,
                    isAvailableWhileDeviceLocked: true,
                ),
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
        groupInviteLink: GroupInviteLink,
    ) -> GroupInviteLinkViewModel {

        let touchMessage = { () async -> Void in
            await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
                SSKEnvironment.shared.databaseStorageRef.touch(interaction: message, shouldReindex: false, tx: transaction)
            }
        }

        guard let groupInviteLinkPreview = GroupManager.cachedGroupInviteLinkPreview(groupInviteLink: groupInviteLink) else {
            // If there is no cached GroupInviteLinkPreview for this link,
            // try to do load it now. On success, touch the interaction
            // in order to trigger reload of the view.
            Task {
                do {
                    let groupContextInfo = GroupV2ContextInfo.deriveFrom(masterKey: groupInviteLink.masterKey)
                    _ = try await SSKEnvironment.shared.groupsV2Ref.fetchGroupInviteLinkPreview(
                        inviteLinkPassword: groupInviteLink.inviteLinkPassword,
                        groupSecretParams: groupContextInfo.groupSecretParams,
                    )
                    _ = Self.updateExpirationList(groupInviteLink: groupInviteLink, isExpired: false)
                    await touchMessage()
                } catch {
                    switch error {
                    case GroupsV2Error.expiredGroupInviteLink,
                         GroupsV2Error.localUserBlockedFromJoining,
                         GroupsV2Error.terminatedGroup:
                        Logger.warn("Failed to fetch group link content: \(error)")
                        if Self.updateExpirationList(groupInviteLink: groupInviteLink, isExpired: true) {
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
                isExpired: Self.isGroupInviteLinkExpired(groupInviteLink: groupInviteLink),
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
                    try await Self.loadGroupInviteLinkAvatar(avatarUrlPath: avatarUrlPath, groupInviteLink: groupInviteLink)
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
