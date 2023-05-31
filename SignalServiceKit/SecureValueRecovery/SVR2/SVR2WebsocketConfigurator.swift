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
    internal var authMethod: SVR.AuthMethod

    init(mrenclave: MrEnclave = TSConstants.svr2Enclave, authMethod: SVR.AuthMethod) {
        self.mrenclave = mrenclave
        self.authMethod = authMethod
    }

    internal static var signalServiceType: SignalServiceType { .svr2 }

    internal static func websocketUrlPath(mrenclaveString: String) -> String {
        return "v1/\(mrenclaveString)"
    }

    internal func fetchAuth() -> Promise<RemoteAttestation.Auth> {
        if let credential = authMethod.svr2Auth {
            return .value(credential.credential)
        }
        return RemoteAttestation.authForSVR2(chatServiceAuth: authMethod.chatServiceAuth)
    }

    internal static func client(
        mrenclave: MrEnclave,
        attestationMessage: Data,
        currentDate: Date
    ) throws -> Svr2Client {
        return try Svr2Client.create(
            mrenclave: mrenclave.dataValue,
            attestationMessage: attestationMessage,
            currentDate: currentDate
        )
    }
}

fileprivate extension SVR.AuthMethod {

    var svr2Auth: SVR2AuthCredential? {
        switch self {
        case .svrAuth(let svrAuthCredential, let backup):
            if let svr2 = svrAuthCredential.svr2 {
                return svr2
            }
            return backup?.svr2Auth
        case .chatServerAuth, .implicit:
            return nil
        }
    }

    var chatServiceAuth: ChatServiceAuth {
        switch self {
        case .svrAuth(_, let backup):
            return backup?.chatServiceAuth ?? .implicit()
        case .chatServerAuth(let authedAccount):
            return authedAccount.chatServiceAuth
        case .implicit:
            return .implicit()
        }
    }
}
