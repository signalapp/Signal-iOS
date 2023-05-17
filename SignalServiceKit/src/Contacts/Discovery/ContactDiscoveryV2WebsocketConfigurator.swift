//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class ContactDiscoveryV2WebsocketConfigurator: SgxWebsocketConfigurator {

    public init() {}

    public func fetchAuth() -> SignalCoreKit.Promise<RemoteAttestation.Auth> {
        return RemoteAttestation.authForCDSI()
    }

    public var mrenclave: MrEnclave { TSConstants.contactDiscoveryV2MrEnclave }

    public static var signalServiceType: SignalServiceType { .contactDiscoveryV2 }

    public static func websocketUrlPath(mrenclaveString: String) -> String {
        return "v1/\(mrenclaveString)/discovery"
    }

    public static func client(
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
