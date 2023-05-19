//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

#if TESTABLE_BUILD

public class MockSgxWebsocketConnectionFactory: SgxWebsocketConnectionFactory {

    private var onConnectAndPerformHandshakeHandlers = [String: ((Any) -> Promise<Any>)]()

    public func setOnConnectAndPerformHandshake<Configurator: SgxWebsocketConfigurator>(
        _ block: @escaping (Configurator) -> Promise<SgxWebsocketConnection<Configurator>>
    ) {
        let key = String(describing: Configurator.self)
        self.onConnectAndPerformHandshakeHandlers[key] = {
            return block($0 as! Configurator).map(on: SyncScheduler()) { $0 }
        }
    }

    public func connectAndPerformHandshake<Configurator: SgxWebsocketConfigurator>(
        configurator: Configurator,
        on queue: DispatchQueue
    ) -> Promise<SgxWebsocketConnection<Configurator>> {
        let key = String(describing: Configurator.self)
        return onConnectAndPerformHandshakeHandlers[key]!(configurator).map(on: SyncScheduler()) { $0 as! SgxWebsocketConnection<Configurator> }
    }
}

#endif
