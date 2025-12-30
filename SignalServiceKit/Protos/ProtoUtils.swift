//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

// TODO: Convert to enum once no objc depends on this.
@objc
class ProtoUtils: NSObject {

    @objc
    static func addLocalProfileKeyIfNecessary(_ thread: TSThread, dataMessageBuilder: SSKProtoDataMessageBuilder, transaction: DBReadTransaction) {
        if shouldMessageHaveLocalProfileKey(thread, transaction: transaction) {
            dataMessageBuilder.setProfileKey(localProfileKey(tx: transaction).serialize())
        }
    }

    @objc
    static func addLocalProfileKeyIfNecessary(forThread thread: TSThread, profileKeySnapshot: Data?, dataMessageBuilder: SSKProtoDataMessageBuilder, transaction: DBReadTransaction) {
        let profileKey = localProfileKey(tx: transaction)
        let canAddLocalProfileKey: Bool = (
            profileKeySnapshot?.ows_constantTimeIsEqual(to: profileKey.serialize()) == true
                || shouldMessageHaveLocalProfileKey(thread, transaction: transaction),
        )
        if canAddLocalProfileKey {
            dataMessageBuilder.setProfileKey(profileKey.serialize())
        }
    }

    @objc
    static func addLocalProfileKeyIfNecessary(_ thread: TSThread, callMessageBuilder: SSKProtoCallMessageBuilder, transaction: DBReadTransaction) {
        if shouldMessageHaveLocalProfileKey(thread, transaction: transaction) {
            callMessageBuilder.setProfileKey(localProfileKey(tx: transaction).serialize())
        }
    }

    static func localProfileKey(tx: DBReadTransaction) -> ProfileKey {
        let profileManager = SSKEnvironment.shared.profileManagerRef
        // Force unwrap is from the original ObjC implementation. It is "safe"
        // because we generate missing profile keys in warmCaches.
        return profileManager.localProfileKey(tx: tx)!
    }

    private static func shouldMessageHaveLocalProfileKey(_ thread: TSThread, transaction: DBReadTransaction) -> Bool {
        // Group threads will return YES if the group is in the whitelist
        // Contact threads will return YES if the contact is in the whitelist.
        SSKEnvironment.shared.profileManagerRef.isThread(inProfileWhitelist: thread, transaction: transaction)
    }
}
