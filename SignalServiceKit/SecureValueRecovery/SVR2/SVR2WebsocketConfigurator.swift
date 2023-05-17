//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

public class SVR2WebsocketConfigurator: SgxWebsocketConfigurator {

    public let mrenclave: MrEnclave

    private init(mrenclave: MrEnclave) {
        self.mrenclave = mrenclave
    }

    public init() {
        self.mrenclave = TSConstants.svr2Enclave
    }

    public static func forPastEnclave(_ enclave: MrEnclave) -> SVR2WebsocketConfigurator {
        return SVR2WebsocketConfigurator(mrenclave: enclave)
    }

    public static var signalServiceType: SignalServiceType { .svr2 }

    public static func websocketUrlPath(mrenclaveString: String) -> String {
        return "v1/\(mrenclaveString)"
    }

    public func fetchAuth() -> SignalCoreKit.Promise<RemoteAttestation.Auth> {
        fatalError("Auth for SVR2 is unimplemented")
    }

    public static func client(
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
