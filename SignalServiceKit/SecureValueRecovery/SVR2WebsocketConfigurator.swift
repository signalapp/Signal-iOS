//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

class SVR2WebsocketConfigurator: SgxWebsocketConfigurator {

    typealias Request = SVR2Proto_Request
    typealias Response = SVR2Proto_Response
    typealias Client = Svr2Client

    let mrenclave: MrEnclave
    var authMethod: SVR2.AuthMethod
    let remoteAttestationAuthFetcher: RemoteAttestationAuthFetcher

    init(
        mrenclave: MrEnclave,
        authMethod: SVR2.AuthMethod,
        remoteAttestationAuthFetcher: RemoteAttestationAuthFetcher,
    ) {
        self.mrenclave = mrenclave
        self.authMethod = authMethod
        self.remoteAttestationAuthFetcher = remoteAttestationAuthFetcher
    }

    static var signalServiceType: SignalServiceType { .svr2 }

    static func websocketUrlPath(mrenclaveString: String) -> String {
        return "v1/\(mrenclaveString)"
    }

    func fetchAuth() async throws -> RemoteAttestationAuth {
        switch authMethod {
        case .svrAuth(let credential, _):
            return credential.credential
        case .chatServerAuth(let authedAccount):
            return try await remoteAttestationAuthFetcher.fetchAuth(
                forService: .svr2,
                chatServiceAuth: authedAccount.chatServiceAuth,
            )
        case .implicit:
            return try await remoteAttestationAuthFetcher.fetchAuth(
                forService: .svr2,
                chatServiceAuth: .implicit(),
            )
        }
    }

    static func client(
        mrenclave: MrEnclave,
        attestationMessage: Data,
        currentDate: Date,
    ) throws -> Svr2Client {
        return try Svr2Client(
            mrenclave: mrenclave.dataValue,
            attestationMessage: attestationMessage,
            currentDate: currentDate,
        )
    }
}
