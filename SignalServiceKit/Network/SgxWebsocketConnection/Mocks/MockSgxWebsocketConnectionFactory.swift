//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

final public class MockSgxWebsocketConnectionFactory: SgxWebsocketConnectionFactory {

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
        on scheduler: Scheduler
    ) -> Promise<SgxWebsocketConnection<Configurator>> {
        let key = String(describing: Configurator.self)
        return onConnectAndPerformHandshakeHandlers[key]!(configurator).map(on: scheduler) { $0 as! SgxWebsocketConnection<Configurator> }
    }
}

#endif
