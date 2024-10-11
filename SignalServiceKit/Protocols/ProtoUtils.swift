//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// TODO: Convert to enum once no objc depends on this.
@objc
internal class ProtoUtils: NSObject {

    @objc
    internal static func addLocalProfileKeyIfNecessary(_ thread: TSThread, dataMessageBuilder: SSKProtoDataMessageBuilder, transaction: SDSAnyReadTransaction) {
        if shouldMessageHaveLocalProfileKey(thread, transaction: transaction) {
            dataMessageBuilder.setProfileKey(localProfileKey.keyData)
        }
    }

    @objc
    internal static func addLocalProfileKey(toDataMessageBuilder dataMessageBuilder: SSKProtoDataMessageBuilder) {
        dataMessageBuilder.setProfileKey(localProfileKey.keyData)
    }

    @objc
    internal static func addLocalProfileKeyIfNecessary(_ thread: TSThread, callMessageBuilder: SSKProtoCallMessageBuilder, transaction: SDSAnyReadTransaction) {
        if shouldMessageHaveLocalProfileKey(thread, transaction: transaction) {
            callMessageBuilder.setProfileKey(localProfileKey.keyData)
        }
    }

    private static var localProfileKey: Aes256Key {
        SSKEnvironment.shared.profileManagerRef.localProfileKey
    }

    private static func shouldMessageHaveLocalProfileKey(_ thread: TSThread, transaction: SDSAnyReadTransaction) -> Bool {
        // Group threads will return YES if the group is in the whitelist
        // Contact threads will return YES if the contact is in the whitelist.
        SSKEnvironment.shared.profileManagerRef.isThread(inProfileWhitelist: thread, transaction: transaction)
    }
}
