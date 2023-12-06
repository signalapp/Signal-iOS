//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension TSInfoMessage {
    @objc(TSInfoMessageUpdateMessages)
    public class PersistableGroupUpdateItemsWrapper: NSObject, NSCopying, NSSecureCoding {
        public let updateItems: [PersistableGroupUpdateItem]

        public init(_ updateItems: [PersistableGroupUpdateItem]) {
            self.updateItems = updateItems
        }

        // MARK: NSCopying

        public func copy(with _: NSZone? = nil) -> Any {
            self
        }

        // MARK: NSSecureCoding

        public static var supportsSecureCoding: Bool { true }

        private static let messagesKey = "messagesKey"

        public func encode(with aCoder: NSCoder) {
            let jsonEncoder = JSONEncoder()
            do {
                let messagesData = try jsonEncoder.encode(updateItems)
                aCoder.encode(messagesData, forKey: Self.messagesKey)
            } catch let error {
                owsFailDebug("Failed to encode updateItems data: \(error)")
                return
            }
        }

        public required init?(coder aDecoder: NSCoder) {
            guard let updateItemsData = aDecoder.decodeObject(
                forKey: Self.messagesKey
            ) as? Data else {
                owsFailDebug("Failed to decode updateItems data")
                return nil
            }

            let jsonDecoder = JSONDecoder()
            do {
                updateItems = try jsonDecoder.decode(
                    [PersistableGroupUpdateItem].self,
                    from: updateItemsData
                )
            } catch let error {
                owsFailDebug("Failed to decode updateItems data: \(error)")
                return nil
            }

            super.init()
        }
    }
}

// MARK: -

extension TSInfoMessage {
    public enum PersistableGroupUpdateItem: Codable {
        enum CodingKeys: String, CodingKey {
            case sequenceOfInviteLinkRequestAndCancels
            case invitedPniPromotedToFullMemberAci
            case inviteRemoved
        }

        case sequenceOfInviteLinkRequestAndCancels(count: UInt, isTail: Bool)
        case invitedPniPromotedToFullMemberAci(pni: PniUuid, aci: AciUuid)
        case inviteRemoved(invitee: ServiceIdUppercaseString, wasLocalUser: Bool)
    }
}
