//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Describes a message that is being replied to in a draft.
public struct ThreadReplyInfo: Codable {
    public let timestamp: UInt64
    public let author: ServiceId

    public init(timestamp: UInt64, author: ServiceId) {
        self.timestamp = timestamp
        self.author = author
    }
}

public class ThreadReplyInfoObjC: NSObject {
    private let wrappedValue: ThreadReplyInfo

    public init(_ wrappedValue: ThreadReplyInfo) {
        self.wrappedValue = wrappedValue
    }

    @objc
    func save(threadUniqueId: String, tx: SDSAnyWriteTransaction) {
        DependenciesBridge.shared.threadReplyInfoStore.save(wrappedValue, for: threadUniqueId, tx: tx.asV2Write)
    }

    @objc
    static func delete(threadUniqueId: String, tx: SDSAnyWriteTransaction) {
        DependenciesBridge.shared.threadReplyInfoStore.remove(for: threadUniqueId, tx: tx.asV2Write)
    }
}
