//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

/// Wraps the LibSignal Key Transparency network calls, so they can be mocked.
protocol KeyTransparencyApiClient {
    func check(
        for mode: KeyTransparency.CheckMode,
        aciInfo: KeyTransparency.AciInfo,
        e164Info: KeyTransparency.E164Info?,
        usernameHash: Data?,
    ) async throws
}

// MARK: -

final class KeyTransparencyApiClientImpl: KeyTransparencyApiClient {
    private let chatConnectionManager: ChatConnectionManager
    private let db: DB
    private let keyTransparencyStore: KeyTransparencyStore

    init(
        chatConnectionManager: ChatConnectionManager,
        db: DB,
        keyTransparencyStore: KeyTransparencyStore,
    ) {
        self.chatConnectionManager = chatConnectionManager
        self.db = db
        self.keyTransparencyStore = keyTransparencyStore
    }

    func check(
        for mode: KeyTransparency.CheckMode,
        aciInfo: KeyTransparency.AciInfo,
        e164Info: KeyTransparency.E164Info?,
        usernameHash: Data?,
    ) async throws {
        let ktClient = try await chatConnectionManager.keyTransparencyClient()

        try await ktClient.check(
            for: mode,
            account: aciInfo,
            e164: e164Info,
            usernameHash: usernameHash,
            store: KeyTransparencyStoreForLibSignal(
                db: db,
                keyTransparencyStore: keyTransparencyStore,
            ),
        )
    }
}
