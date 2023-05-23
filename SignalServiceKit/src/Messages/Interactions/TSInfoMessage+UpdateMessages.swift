//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension TSInfoMessage {
    public enum UpdateMessage: Codable, CustomStringConvertible {
        enum CodingKeys: String, CodingKey {
            case sequenceOfInviteLinkRequestAndCancels
            case invitedPniPromotedToFullMemberAci
            case inviteRemoved
        }

        case sequenceOfInviteLinkRequestAndCancels(count: UInt, isTail: Bool)
        case invitedPniPromotedToFullMemberAci(pni: ServiceId, aci: ServiceId)
        case inviteRemoved(invitee: ServiceId, wasLocalUser: Bool)

        public var description: String {
            switch self {
            case let .sequenceOfInviteLinkRequestAndCancels(count, isTail):
                return "sequenceOfInviteLinkRequestAndCancels: { count: \(count), isTail: \(isTail) }"
            case let .invitedPniPromotedToFullMemberAci(pni, aci):
                return "invitedPniPromotedToFullMemberAci: { pni: \(pni), aci: \(aci) }"
            case let .inviteRemoved(invitee, wasLocalUser):
                return "inviteRemoved: { invitee: \(invitee), wasLocalUser: \(wasLocalUser) }"
            }
        }
    }

    @objc(TSInfoMessageUpdateMessages)
    public class UpdateMessagesWrapper: NSObject, NSCopying, NSSecureCoding {

        public let updateMessages: [UpdateMessage]

        public init(_ updateMessages: [UpdateMessage]) {
            self.updateMessages = updateMessages
        }

        // MARK: - NSCopying

        public func copy(with _: NSZone? = nil) -> Any {
            self
        }

        // MARK: - NSSecureCoding

        public static var supportsSecureCoding: Bool { true }

        private static let messagesKey = "messagesKey"

        public func encode(with aCoder: NSCoder) {
            let jsonEncoder = JSONEncoder()
            do {
                let messagesData = try jsonEncoder.encode(updateMessages)
                aCoder.encode(messagesData, forKey: Self.messagesKey)
            } catch let error {
                owsFailDebug("Failed to encode updateMessages data: \(error)")
                return
            }
        }

        public required init?(coder aDecoder: NSCoder) {
            guard let messagesData = aDecoder.decodeObject(forKey: Self.messagesKey) as? Data else {
                owsFailDebug("Failed to decode updateMessages data")
                return nil
            }

            let jsonDecoder = JSONDecoder()
            do {
                updateMessages = try jsonDecoder.decode([UpdateMessage].self, from: messagesData)
            } catch let error {
                owsFailDebug("Failed to decode updateMessages data: \(error)")
                return nil
            }

            super.init()
        }

        // MARK: Debug description

        public override var debugDescription: String {
            "{ updateMessages: \(updateMessages) }"
        }
    }
}
