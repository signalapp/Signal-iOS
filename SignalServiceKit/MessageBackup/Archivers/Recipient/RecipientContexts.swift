//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension MessageBackup {

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

    public typealias GroupId = Data

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
        public enum Address {

            case contact(ContactAddress)
            case group(GroupId)
        }

        public let localRecipientId: RecipientId

        internal let localIdentifiers: LocalIdentifiers

        private var currentRecipientId: RecipientId
        private let groupIdMap = SharedMap<GroupId, RecipientId>()
        private let contactAciMap = SharedMap<Aci, RecipientId>()
        private let contactPniMap = SharedMap<Pni, RecipientId>()
        private let contactE164ap = SharedMap<E164, RecipientId>()

        internal init(
            localIdentifiers: LocalIdentifiers,
            localRecipientId: RecipientId
        ) {
            self.localIdentifiers = localIdentifiers
            self.localRecipientId = localRecipientId

            // Start after the local recipient id.
            currentRecipientId = RecipientId(localRecipientId.value + 1)

            // Also insert the local identifiers, just in case we try and look
            // up the local recipient by .contact enum case.
            contactAciMap[localIdentifiers.aci] = localRecipientId
            if let pni = localIdentifiers.pni {
                contactPniMap[pni] = localRecipientId
            }
            if let e164 = E164(localIdentifiers.phoneNumber) {
                contactE164ap[e164] = currentRecipientId
            }
        }

        internal func assignRecipientId(to address: Address) -> RecipientId {
            defer {
                currentRecipientId = RecipientId(currentRecipientId.value + 1)
            }
            switch address {
            case .group(let groupId):
                groupIdMap[groupId] = currentRecipientId
            case .contact(let contactAddress):
                // Create mappings for every identifier we know about
                if let aci = contactAddress.aci {
                    contactAciMap[aci] = currentRecipientId
                }
                if let pni = contactAddress.pni {
                    contactPniMap[pni] = currentRecipientId
                }
                if let e164 = contactAddress.e164 {
                    contactE164ap[e164] = currentRecipientId
                }
            }
            return currentRecipientId
        }

        internal subscript(_ address: Address) -> RecipientId? {
            // swiftlint:disable:next implicit_getter
            get {
                switch address {
                case .group(let groupId):
                    return groupIdMap[groupId]
                case .contact(let contactAddress):
                    // Go down identifiers in priority order, return the first we have.
                    if let aci = contactAddress.aci {
                        return contactAciMap[aci]
                    } else if let e164 = contactAddress.e164 {
                        return contactE164ap[e164]
                    } else if let pni = contactAddress.pni {
                        return contactPniMap[pni]
                    } else {
                        return nil
                    }
                }
            }
        }
    }

    public class RecipientRestoringContext {
        public enum Address {
            case localAddress
            case contact(ContactAddress)
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

extension MessageBackup.RecipientId: MessageBackupLoggableId {
    public var typeLogString: String { "BackupProtoRecipient" }

    public var idLogString: String { "\(self.value)" }
}

extension MessageBackup.RecipientArchivingContext.Address: MessageBackupLoggableId {
    public var typeLogString: String {
        switch self {
        case .contact(let address):
            return address.typeLogString
        case .group:
            return "TSGroupThread"
        }
    }

    public var idLogString: String {
        switch self {
        case .contact(let contactAddress):
            return contactAddress.idLogString
        case .group(let groupId):
            // Rely on the scrubber to scrub the id.
            return groupId.base64EncodedString()
        }
    }
}

extension BackupProtoRecipient {

    public var recipientId: MessageBackup.RecipientId {
        return .init(id)
    }
}

extension BackupProtoChat {

    public var recipientId: MessageBackup.RecipientId {
        return .init(self.recipientID)
    }
}

extension BackupProtoChatItem {

    public var authorRecipientId: MessageBackup.RecipientId {
        return .init(authorID)
    }
}

extension BackupProtoReaction {

    public var authorRecipientId: MessageBackup.RecipientId {
        return .init(authorID)
    }
}

extension BackupProtoQuote {

    public var authorRecipientId: MessageBackup.RecipientId {
        return .init(authorID)
    }
}
