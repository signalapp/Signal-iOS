//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/// An outgoing group v2 update.
final class OutgoingGroupUpdateMessage: TSOutgoingMessage {
    required init?(coder: NSCoder) {
        self.isDeletingAccount = coder.decodeObject(of: NSNumber.self, forKey: "isDeletingAccount")?.boolValue ?? false
        self.isUpdateUrgent = coder.decodeObject(of: NSNumber.self, forKey: "isUpdateUrgent")?.boolValue ?? false
        super.init(coder: coder)
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(NSNumber(value: self.isDeletingAccount), forKey: "isDeletingAccount")
        coder.encode(NSNumber(value: self.isUpdateUrgent), forKey: "isUpdateUrgent")
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(isDeletingAccount)
        hasher.combine(isUpdateUrgent)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.isDeletingAccount == object.isDeletingAccount else { return false }
        guard self.isUpdateUrgent == object.isUpdateUrgent else { return false }
        return true
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        let result = super.copy(with: zone) as! Self
        result.isDeletingAccount = self.isDeletingAccount
        result.isUpdateUrgent = self.isUpdateUrgent
        return result
    }

    private var isUpdateUrgent: Bool = false
    private(set) var isDeletingAccount: Bool = false

    init(
        in thread: TSGroupThread,
        groupMetaMessage: TSGroupMetaMessage,
        expiresInSeconds: UInt32 = 0,
        groupChangeProtoData: Data? = nil,
        additionalRecipients: some Sequence<ServiceId>,
        isUrgent: Bool = false,
        isDeletingAccount: Bool = false,
        transaction: DBReadTransaction,
    ) {
        let builder: TSOutgoingMessageBuilder = .withDefaultValues(
            thread: thread,
            expiresInSeconds: expiresInSeconds,
            groupMetaMessage: groupMetaMessage,
            groupChangeProtoData: groupChangeProtoData,
        )
        self.isUpdateUrgent = isUrgent
        self.isDeletingAccount = isDeletingAccount
        super.init(
            outgoingMessageWith: builder,
            additionalRecipients: additionalRecipients.map { ServiceIdObjC.wrapValue($0) },
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: transaction,
        )
    }

    override var isUrgent: Bool { self.isUpdateUrgent }

    override var shouldBeSaved: Bool { false }
}
