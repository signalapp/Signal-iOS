//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

internal class SVR2WebsocketConfigurator: SgxWebsocketConfigurator {

    internal typealias Request = SVR2Proto_Request
    internal typealias Response = SVR2Proto_Response

    internal let mrenclave: MrEnclave

    private init(mrenclave: MrEnclave) {
        self.mrenclave = mrenclave
    }

    internal init() {
        self.mrenclave = TSConstants.svr2Enclave
    }

    internal static func forPastEnclave(_ enclave: MrEnclave) -> SVR2WebsocketConfigurator {
        return SVR2WebsocketConfigurator(mrenclave: enclave)
    }

    internal static var signalServiceType: SignalServiceType { .svr2 }

    internal static func websocketUrlPath(mrenclaveString: String) -> String {
        return "v1/\(mrenclaveString)"
    }

    internal func fetchAuth() -> SignalCoreKit.Promise<RemoteAttestation.Auth> {
        fatalError("Auth for SVR2 is unimplemented")
    }

    internal static func client(
        mrenclave: MrEnclave,
        attestationMessage: Data,
        currentDate: Date
    ) throws -> LibSignalClient.SgxClient {
        #if DEBUG
        return try Svr2Client.create_NOT_FOR_PRODUCTION(
            mrenclave: mrenclave.dataValue,
            attestationMessage: attestationMessage,
            currentDate: currentDate
        )
        #else
        owsFail("SVR2 unavailable")
        #endif
    }
}
