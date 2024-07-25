//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension LinkPreviewManagerImpl {
    public enum Shims {
        public typealias GroupsV2 = _LinkPreviewManagerImpl_GroupsV2Shim
        public typealias SSKPreferences = _LinkPreviewManagerImpl_SSKPreferencesShim
    }
    public enum Wrappers {
        public typealias GroupsV2 = _LinkPreviewManagerImpl_GroupsV2Wrapper
        public typealias SSKPreferences = _LinkPreviewManagerImpl_SSKPreferencesWrapper
    }
}

// MARK: - GroupsV2

public protocol _LinkPreviewManagerImpl_GroupsV2Shim {

    func fetchGroupInviteLinkPreview(
        inviteLinkPassword: Data?,
        groupSecretParamsData: Data,
        allowCached: Bool
    ) -> Promise<GroupInviteLinkPreview>

    func fetchGroupInviteLinkAvatar(
        avatarUrlPath: String,
        groupSecretParamsData: Data
    ) -> Promise<Data>
}

public class _LinkPreviewManagerImpl_GroupsV2Wrapper: _LinkPreviewManagerImpl_GroupsV2Shim {

    private let groupsV2: GroupsV2

    public init(_ groupsV2: GroupsV2) {
        self.groupsV2 = groupsV2
    }

    public func fetchGroupInviteLinkPreview(
        inviteLinkPassword: Data?,
        groupSecretParamsData: Data,
        allowCached: Bool
    ) -> Promise<GroupInviteLinkPreview> {
        Promise.wrapAsync {
            return try await self.groupsV2.fetchGroupInviteLinkPreview(
                inviteLinkPassword: inviteLinkPassword,
                groupSecretParamsData: groupSecretParamsData,
                allowCached: allowCached
            )
        }
    }

    public func fetchGroupInviteLinkAvatar(
        avatarUrlPath: String,
        groupSecretParamsData: Data
    ) -> Promise<Data> {
        Promise.wrapAsync {
            return try await self.groupsV2.fetchGroupInviteLinkAvatar(
                avatarUrlPath: avatarUrlPath,
                groupSecretParamsData: groupSecretParamsData
            )
        }
    }
}

// MARK: - SSKPreferences

public protocol _LinkPreviewManagerImpl_SSKPreferencesShim {

    func areLinkPreviewsEnabled(tx: DBReadTransaction) -> Bool
}

public class _LinkPreviewManagerImpl_SSKPreferencesWrapper: _LinkPreviewManagerImpl_SSKPreferencesShim {

    public init() {}

    public func areLinkPreviewsEnabled(tx: DBReadTransaction) -> Bool {
        return SSKPreferences.areLinkPreviewsEnabled(transaction: SDSDB.shimOnlyBridge(tx))
    }
}
