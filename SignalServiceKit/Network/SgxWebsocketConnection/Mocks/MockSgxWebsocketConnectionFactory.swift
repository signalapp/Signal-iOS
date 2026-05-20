//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class MockSgxWebsocketConnectionFactory: SgxWebsocketConnectionFactory {

    private var onConnectAndPerformHandshakeHandlers = [String: (Any) async throws -> Any]()

    public func setOnConnectAndPerformHandshake<Configurator: SgxWebsocketConfigurator>(
        _ block: @escaping (Configurator) async throws -> SgxWebsocketConnection<Configurator>,
    ) {
        let key = String(describing: Configurator.self)
        self.onConnectAndPerformHandshakeHandlers[key] = { try await block($0 as! Configurator) }
    }

    public func connectAndPerformHandshake<Configurator: SgxWebsocketConfigurator>(
        configurator: Configurator,
    ) async throws -> SgxWebsocketConnection<Configurator> {
        let key = String(describing: Configurator.self)
        return try await onConnectAndPerformHandshakeHandlers[key]!(configurator) as! SgxWebsocketConnection<Configurator>
    }
}

#endif
