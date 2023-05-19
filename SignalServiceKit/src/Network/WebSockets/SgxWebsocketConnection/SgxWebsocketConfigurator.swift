//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit
import SwiftProtobuf

/// Defines configuration for a websocket connection to an `SgxClient`-compliant server.
/// Besides defining constant values used to establish the connection (url, mrenclave),
/// handles fetching of authentication headers used when opening the websocket,
/// and creation of the LibSignal-provided `SgxClient`.
public protocol SgxWebsocketConfigurator {

    associatedtype Request: SwiftProtobuf.Message
    associatedtype Response: SwiftProtobuf.Message

    /// MrEnclave to use for the websocket connection.
    /// Typically points to a TSConstants value.
    var mrenclave: MrEnclave { get }

    /// SignalServiceType to use for the websocket connection, e.g. which
    /// root url to hit. (See information in `SignalServiceInfo`)
    static var signalServiceType: SignalServiceType { get }

    /// Path to the endpoint for initiating the websocket connection.
    /// `mrEnclaveString` is the encoded MrEnclave defined in this very class.
    static func websocketUrlPath(mrenclaveString: String) -> String

    /// Called internally in order to fetch authentication to include in the header
    /// when establishing the initial websocket connection.
    func fetchAuth() -> Promise<RemoteAttestation.Auth>

    /// Called just after starting a websocket connection in order to use the
    /// client for the handshake and subsequent messages.
    /// This class is expected to instantiate a new `SgxClient` at call time,
    /// and produce a new client if called more than once.
    ///
    /// - Parameters:
    ///   - mrenclave: The MrEnclave to use. (Which comes from the `mrEnclave`
    ///   instance var on this very class, but passed into this static context.)
    ///   - attestationMessage: Raw bytes of attestation received over the
    ///   websocket when the connection was opened.
    ///   - currentDate: the current date, for use in the SgxClient.
    static func client(
        mrenclave: MrEnclave,
        attestationMessage: Data,
        currentDate: Date
    ) throws -> SgxClient

    /// Name to use for logging connection events. Defaults to class name.
    static var loggingName: String { get }
}

extension SgxWebsocketConfigurator {

    public static var loggingName: String {
        return String(describing: Self.self)
    }
}
