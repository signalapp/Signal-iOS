//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension CloudBackup {

    public struct RecipientId: ExpressibleByIntegerLiteral, Hashable {

        public typealias IntegerLiteralType = UInt64

        internal let value: UInt64

        public init(integerLiteral value: UInt64) {
            self.value = value
        }

        fileprivate init(_ value: UInt64) {
            self.value = value
        }
    }

    /**
     * As we go archiving recipients, we use this object to track mappings from the addressing we use in the app
     * to the ID addressing system of the backup protos.
     *
     * For example, we will assign a ``BackupRecipientId`` to each ``SignalRecipient`` as we
     * insert them. Later, when we create the ``BackupProtoChat`` corresponding to the ``TSContactThread``
     * for that recipient, we will need to add the corresponding ``BackupRecipientId``, which we look up
     * using the contact's Aci/Pni/e164, from the map this context keeps.
     */
    public class RecipientArchivingContext {
        public enum Address: Hashable {
            public typealias GroupId = Data

            case noteToSelf
            case contactAci(Aci)
            case contactPni(Pni)
            case contactE164(E164)
            case group(GroupId)
        }

        internal let localIdentifiers: LocalIdentifiers

        private var currentRecipientId: RecipientId = 0
        private let map = SharedMap<Address, RecipientId>()

        internal init(localIdentifiers: LocalIdentifiers) {
            self.localIdentifiers = localIdentifiers
        }

        internal func assignRecipientId(to address: Address) -> RecipientId {
            defer {
                currentRecipientId = RecipientId(currentRecipientId.value + 1)
            }
            map[address] = currentRecipientId
            return currentRecipientId
        }

        internal subscript(_ address: Address) -> RecipientId? {
            // swiftlint:disable:next implicit_getter
            get { map[address] }
        }
    }

    public class RecipientRestoringContext {
        public enum Address {
            public typealias GroupId = RecipientArchivingContext.Address.GroupId

            case noteToSelf
            case contact(aci: Aci?, pni: Pni?, e164: E164?)
            case group(GroupId)
        }

        internal let localIdentifiers: LocalIdentifiers

        private let map = SharedMap<RecipientId, Address>()

        internal init(localIdentifiers: LocalIdentifiers) {
            self.localIdentifiers = localIdentifiers
        }

        internal subscript(_ id: RecipientId) -> Address? {
            get { map[id] }
            set(newValue) { map[id] = newValue }
        }
    }
}

extension BackupProtoRecipient {

    public var recipientId: CloudBackup.RecipientId {
        return .init(id)
    }
}

extension BackupProtoChat {

    public var recipientId: CloudBackup.RecipientId {
        return .init(self.recipientID)
    }
}

extension BackupProtoChatItem {

    public var authorRecipientId: CloudBackup.RecipientId {
        return .init(authorID)
    }
}

extension BackupProtoReaction {

    public var authorRecipientId: CloudBackup.RecipientId {
        return .init(authorID)
    }
}
