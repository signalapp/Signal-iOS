//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

internal class ContactDiscoveryV2WebsocketConfigurator: SgxWebsocketConfigurator {

    internal typealias Request = CDSI_ClientRequest
    internal typealias Response = CDSI_ClientResponse

    internal init() {}

    internal func fetchAuth() -> SignalCoreKit.Promise<RemoteAttestation.Auth> {
        return RemoteAttestation.authForCDSI()
    }

    internal var mrenclave: MrEnclave { TSConstants.contactDiscoveryV2MrEnclave }

    internal static var signalServiceType: SignalServiceType { .contactDiscoveryV2 }

    internal static func websocketUrlPath(mrenclaveString: String) -> String {
        return "v1/\(mrenclaveString)/discovery"
    }

    internal static func client(
        mrenclave: MrEnclave,
        attestationMessage: Data,
        currentDate: Date
    ) throws -> SgxClient {
        return try Cds2Client(
            mrenclave: mrenclave.dataValue,
            attestationMessage: attestationMessage,
            currentDate: currentDate
        )
    }
}
