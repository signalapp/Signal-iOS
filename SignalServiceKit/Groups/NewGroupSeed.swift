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

    public let groupSecretParams: GroupSecretParams

    public init() {
        let groupSecretParams = try! GroupSecretParams.generate()
        self.groupSecretParams = groupSecretParams
    }
}
