//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

// This seed can be used to pre-generate the key group
// state before the group is created.  This allows us
// to preview the correct conversation color, etc. in
// the "new group" view.
@objc
public class NewGroupSeed: NSObject {

    // MARK: - Dependencies

    private class var groupsV2: GroupsV2 {
        return SSKEnvironment.shared.groupsV2
    }

    // MARK: -

    @objc
    public let groupIdV1: Data

    @objc
    public let groupIdV2: Data?
    @objc
    public let groupSecretParamsData: Data?

    @objc
    public override convenience init() {
        self.init(groupIdV1: nil)
    }

    private init(groupIdV1: Data? = nil) {
        if let groupIdV1 = groupIdV1 {
            self.groupIdV1 = groupIdV1
        } else {
            self.groupIdV1 = TSGroupModel.generateRandomV1GroupId()
        }

        let groupsV2 = NewGroupSeed.groupsV2
        let groupSecretParamsData = try! groupsV2.generateGroupSecretParamsData()
        self.groupSecretParamsData = groupSecretParamsData
        groupIdV2 = try! groupsV2.groupId(forGroupSecretParamsData: groupSecretParamsData)
    }

    // During the v1->v2 transition period, we don't know whether
    // a new group will be v1 or v2 until we make it.  So we guess.
    // This is only used for color previews so it's okay to be
    // inaccurate.
    @objc
    public var possibleGroupId: Data {
        if let groupIdV2 = groupIdV2 {
            return groupIdV2
        }
        return groupIdV1
    }

    @objc
    public var possibleConversationColorName: ConversationColorName {
        return TSGroupThread.defaultConversationColorName(forGroupId: possibleGroupId)
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
