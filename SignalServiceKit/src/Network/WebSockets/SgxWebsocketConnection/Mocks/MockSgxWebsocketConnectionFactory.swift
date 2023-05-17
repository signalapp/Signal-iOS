//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

#if TESTABLE_BUILD

public class MockSgxWebsocketConnectionFactory: SgxWebsocketConnectionFactory {

    public var onConnectAndPerformHandshake: ((
        _ configurator: SgxWebsocketConfigurator,
        _ queue: DispatchQueue
    ) -> Promise<SgxWebsocketConnection> )?

    func connectAndPerformHandshake<Configurator>(
        configurator: Configurator,
        on queue: DispatchQueue
    ) -> Promise<SgxWebsocketConnection> where Configurator: SgxWebsocketConfigurator {
        onConnectAndPerformHandshake!(configurator, queue)
    }
}

#endif
