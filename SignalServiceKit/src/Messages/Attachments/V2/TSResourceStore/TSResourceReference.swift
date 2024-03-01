//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct TSResourceReference {
    public let id: TSResourceId

    /// Filename from the sender, used for rendering as a file attachment.
    /// NOT the same as the file name on disk.
    public let sourceFilename: String?

    private let fetcher: (DBReadTransaction) -> TSResource?

    internal init(
        id: TSResourceId,
        sourceFilename: String?,
        fetcher: @escaping (DBReadTransaction) -> TSResource?
    ) {
        self.id = id
        self.sourceFilename = sourceFilename
        self.fetcher = fetcher
    }

    public func fetch(tx: DBReadTransaction) -> TSResource? {
        return fetcher(tx)
    }
}

public struct TSResourceReferences {
    public let references: [TSResourceReference]
    private let fetcher: (DBReadTransaction) -> [TSResource]

    internal init(references: [TSResourceReference], fetcher: @escaping (DBReadTransaction) -> [TSResource]) {
        self.references = references
        self.fetcher = fetcher
    }

    static var empty: TSResourceReferences {
        return .init(references: [], fetcher: { _ in return [] })
    }

    public func fetchAll(tx: DBReadTransaction) -> [TSResource] {
        return fetcher(tx)
    }
}
