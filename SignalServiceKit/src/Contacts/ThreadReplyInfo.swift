//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// Describes a message that is being replied to in a draft.
@objc(TSThreadReplyInfo)
public class ThreadReplyInfo: NSObject {
    private struct InternalContents: Codable {
        public var timestamp: UInt64
        public var author: SignalServiceAddress
    }
    private let internalContents: InternalContents
    private static let keyValueStore = SDSKeyValueStore(collection: "TSThreadReplyInfo")

    @objc
    public init(timestamp: UInt64, authorAddress: SignalServiceAddress) {
        internalContents = InternalContents(timestamp: timestamp, author: authorAddress)
    }

    @objc
    public init?(threadUniqueID: String, transaction: SDSAnyReadTransaction) {
        guard let encoded = Self.keyValueStore.getData(threadUniqueID, transaction: transaction) else {
            return nil
        }
        guard let decoded = try? JSONDecoder().decode(InternalContents.self, from: encoded) else {
            return nil
        }
        internalContents = decoded
    }

    @objc
    public var timestamp: UInt64 {
        internalContents.timestamp
    }

    @objc
    public var author: SignalServiceAddress {
        internalContents.author
    }

    @objc
    public func save(threadUniqueID: String, transaction: SDSAnyWriteTransaction) throws {
        try Self.keyValueStore.setData(JSONEncoder().encode(internalContents),
                                       key: threadUniqueID,
                                       transaction: transaction)
    }

    @objc
    public static func delete(threadUniqueID: String, transaction: SDSAnyWriteTransaction) {
        keyValueStore.removeValue(forKey: threadUniqueID, transaction: transaction)
    }
}
