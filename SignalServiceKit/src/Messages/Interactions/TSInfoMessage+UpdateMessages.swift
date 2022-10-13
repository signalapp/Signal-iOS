//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension TSInfoMessage {
    @objc(TSInfoMessageUpdateMessages)
    public class UpdateMessages: NSObject, NSCopying, NSSecureCoding {
        public enum Message: Codable, CustomStringConvertible {
            case sequenceOfInviteLinkRequestAndCancels(count: UInt, isTail: Bool)

            public var description: String {
                switch self {
                case .sequenceOfInviteLinkRequestAndCancels(let count, let isTail):
                    return "sequenceOfInviteLinkRequestAndCancels: { count: \(count), isTail: \(isTail) }"
                }
            }
        }

        public let messages: [Message]

        public convenience init(_ message: Message) {
            self.init([message])
        }

        public init(_ messages: [Message]) {
            self.messages = messages
        }

        public var asSingleMessage: Message? {
            guard messages.count == 1 else {
                return nil
            }

            return messages.first
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
                let messagesData = try jsonEncoder.encode(messages)
                aCoder.encode(messagesData, forKey: Self.messagesKey)
            } catch let error {
                owsFailDebug("Failed to encode messages data: \(error)")
                return
            }
        }

        public required init?(coder aDecoder: NSCoder) {
            guard let messagesData = aDecoder.decodeObject(forKey: Self.messagesKey) as? Data else {
                owsFailDebug("Failed to decode messages data")
                return nil
            }

            let jsonDecoder = JSONDecoder()
            do {
                messages = try jsonDecoder.decode([Message].self, from: messagesData)
            } catch let error {
                owsFailDebug("Failed to decode messages data: \(error)")
                return nil
            }

            super.init()
        }

        // MARK: Debug description

        public override var debugDescription: String {
            "{ messages: \(messages) }"
        }
    }
}
