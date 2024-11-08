//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

// This seed can be used to pre-generate the key group
// state before the group is created.  This allows us
// to preview the correct conversation color, etc. in
// the "new group" view.
public struct NewGroupSeed {

    public let groupIdV1: Data
    public let groupIdV2: Data
    public let groupSecretParams: GroupSecretParams

    public init() {
        self.init(groupIdV1: TSGroupModel.generateRandomGroupId(.V1))
    }

    private init(groupIdV1: Data) {
        self.groupIdV1 = groupIdV1
        let groupSecretParams = try! GroupSecretParams.generate()
        self.groupSecretParams = groupSecretParams
        self.groupIdV2 = try! groupSecretParams.getPublicParams().getGroupIdentifier().serialize().asData
    }

    public var deriveNewGroupSeedForRetry: NewGroupSeed {
        // If group creation fails, we generate a new seed before retrying.
        // We want to re-use the same group id for v1 but generate a new
        // group id / group secret params for v2.
        //
        // v1 group creation can fail after having informed some of the members
        // and/or inserting the group into the local database.
        // In this case, it's important that retries use the same group id.
        // Otherwise members may see multiple groups created.
        //
        // v2 group creation will never fail after having informed some of the
        // members and/or inserting the group into the local database.
        // However, v2 group creation can fail before or after the group is
        // created on the service.  (Re-)trying to create the group on the
        // service a second time using the same group id/secrets params will
        // fail, so it's best to generate a new group id / group secret params
        // for v2.
        NewGroupSeed(groupIdV1: groupIdV1)
    }
}
