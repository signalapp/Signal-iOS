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
    internal typealias Client = Svr2Client

    internal let mrenclave: MrEnclave
    internal var authMethod: SVR2.AuthMethod

    init(mrenclave: MrEnclave = TSConstants.svr2Enclave, authMethod: SVR2.AuthMethod) {
        self.mrenclave = mrenclave
        self.authMethod = authMethod
    }

    internal static var signalServiceType: SignalServiceType { .svr2 }

    internal static func websocketUrlPath(mrenclaveString: String) -> String {
        return "v1/\(mrenclaveString)"
    }

    internal func fetchAuth() -> Promise<RemoteAttestation.Auth> {
        switch authMethod {
        case .svrAuth(let credential, _):
            return .value(credential.credential)
        case .chatServerAuth(let authedAccount):
            return RemoteAttestation.authForSVR2(chatServiceAuth: authedAccount.chatServiceAuth)
        case .implicit:
            return RemoteAttestation.authForSVR2(chatServiceAuth: .implicit())
        }
    }

    internal static func client(
        mrenclave: MrEnclave,
        attestationMessage: Data,
        currentDate: Date
    ) throws -> Svr2Client {
        return try Svr2Client.init(
            mrenclave: mrenclave.dataValue,
            attestationMessage: attestationMessage,
            currentDate: currentDate
        )
    }
}
