//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/// Describes a message that is being replied to in a draft.
public struct ThreadReplyInfo: Codable {
    public let timestamp: UInt64
    @AciUuid public var author: Aci

    public init(timestamp: UInt64, author: Aci) {
        self.timestamp = timestamp
        self._author = author.codableUuid
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
