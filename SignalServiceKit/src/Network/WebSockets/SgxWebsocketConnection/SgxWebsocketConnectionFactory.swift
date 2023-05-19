//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

// MARK: -

protocol SgxWebsocketConnectionFactory {

    /// Connect to an SgxClient-conformant server via websocket and perform the initial handshake.
    ///
    /// - Parameters:
    ///   - queue: The queue to use.
    /// - Returns:
    ///     A Promise for an established connection. If the Promise doesn’t
    ///     resolve to an error, the caller is responsible for ensuring the
    ///     returned connection is properly disconnected.
    func connectAndPerformHandshake<Configurator: SgxWebsocketConfigurator>(
        configurator: Configurator,
        on queue: DispatchQueue
    ) -> Promise<SgxWebsocketConnection<Configurator>>
}

final class SgxWebsocketConnectionFactoryImpl: SgxWebsocketConnectionFactory {

    private let websocketFactory: WebSocketFactory

    public init(websocketFactory: WebSocketFactory) {
        self.websocketFactory = websocketFactory
    }

    func connectAndPerformHandshake<Configurator: SgxWebsocketConfigurator>(
        configurator: Configurator,
        on queue: DispatchQueue
    ) -> Promise<SgxWebsocketConnection<Configurator>> {
        let websocketFactory = self.websocketFactory
        return firstly {
            return configurator.fetchAuth()
        }.then(on: queue) { (auth) -> Promise<SgxWebsocketConnection<Configurator>> in
            return try SgxWebsocketConnectionImpl<Configurator>.connectAndPerformHandshake(
                configurator: configurator,
                auth: auth,
                websocketFactory: websocketFactory,
                queue: queue
            )
        }
    }
}
