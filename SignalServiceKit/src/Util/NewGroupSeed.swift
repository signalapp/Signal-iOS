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
    public override init() {
        groupIdV1 = TSGroupModel.generateRandomV1GroupId()

        if FeatureFlags.tryToCreateNewGroupsV2 {
            let groupsV2 = NewGroupSeed.groupsV2
            let groupSecretParamsData = try! groupsV2.generateGroupSecretParamsData()
            self.groupSecretParamsData = groupSecretParamsData
            groupIdV2 = try! groupsV2.groupId(forGroupSecretParamsData: groupSecretParamsData)
        } else {
            groupSecretParamsData = nil
            groupIdV2 = nil
        }
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
}
