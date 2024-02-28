//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct TSResourceReference {
    public let id: TSResourceId
    private let fetcher: (DBReadTransaction) -> TSResource?

    internal init(id: TSResourceId, fetcher: @escaping (DBReadTransaction) -> TSResource?) {
        self.id = id
        self.fetcher = fetcher
    }

    public func fetch(tx: DBReadTransaction) -> TSResource? {
        return fetcher(tx)
    }
}

public struct TSResourceReferences {
    public let ids: [TSResourceId]
    private let fetcher: (DBReadTransaction) -> [TSResource]

    internal init(ids: [TSResourceId], fetcher: @escaping (DBReadTransaction) -> [TSResource]) {
        self.ids = ids
        self.fetcher = fetcher
    }

    static var empty: TSResourceReferences {
        return .init(ids: [], fetcher: { _ in return [] })
    }

    public func fetch(tx: DBReadTransaction) -> [TSResource] {
        return fetcher(tx)
    }
}
