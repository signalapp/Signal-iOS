//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class MockTSAccountManager: TSAccountManagerProtocol {

    public var dateProvider: DateProvider

    public init(dateProvider: @escaping DateProvider = { Date() }) {
        self.dateProvider = dateProvider
    }

    public var warmCachesMock: (() -> Void)?

    open func warmCaches() {
        warmCachesMock?()
    }

    public var localIdentifiersMock: (() -> LocalIdentifiers?) = {
        return LocalIdentifiers(
            aci: .randomForTesting(),
            pni: .randomForTesting(),
            e164: .init("+15555555555")!
        )
    }

    open var localIdentifiersWithMaybeSneakyTransaction: LocalIdentifiers? { localIdentifiersMock() }

    open func localIdentifiers(tx: DBReadTransaction) -> LocalIdentifiers? {
        return localIdentifiersWithMaybeSneakyTransaction
    }
}
