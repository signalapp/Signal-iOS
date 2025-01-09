//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

// TODO: Convert to enum once no objc depends on this.
@objc
internal class ProtoUtils: NSObject {

    @objc
    internal static func addLocalProfileKeyIfNecessary(_ thread: TSThread, dataMessageBuilder: SSKProtoDataMessageBuilder, transaction: SDSAnyReadTransaction) {
        if shouldMessageHaveLocalProfileKey(thread, transaction: transaction) {
            addLocalProfileKey(toDataMessageBuilder: dataMessageBuilder, transaction: transaction)
        }
    }

    @objc
    internal static func addLocalProfileKey(toDataMessageBuilder dataMessageBuilder: SSKProtoDataMessageBuilder, transaction: SDSAnyReadTransaction) {
        dataMessageBuilder.setProfileKey(localProfileKey(tx: transaction).serialize().asData)
    }

    @objc
    internal static func addLocalProfileKeyIfNecessary(_ thread: TSThread, callMessageBuilder: SSKProtoCallMessageBuilder, transaction: SDSAnyReadTransaction) {
        if shouldMessageHaveLocalProfileKey(thread, transaction: transaction) {
            callMessageBuilder.setProfileKey(localProfileKey(tx: transaction).serialize().asData)
        }
    }

    static func localProfileKey(tx: SDSAnyReadTransaction) -> ProfileKey {
        let profileManager = SSKEnvironment.shared.profileManagerRef
        // Force unwraps are from the original ObjC implementation. They are "safe"
        // because we generate missing profile keys in warmCaches.
        return ProfileKey(profileManager.localUserProfile(tx: tx)!.profileKey!)
    }

    private static func shouldMessageHaveLocalProfileKey(_ thread: TSThread, transaction: SDSAnyReadTransaction) -> Bool {
        // Group threads will return YES if the group is in the whitelist
        // Contact threads will return YES if the contact is in the whitelist.
        SSKEnvironment.shared.profileManagerRef.isThread(inProfileWhitelist: thread, transaction: transaction)
    }
}
