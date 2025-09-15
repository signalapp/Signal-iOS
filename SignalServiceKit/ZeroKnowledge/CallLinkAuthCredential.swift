//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct CallLinkAuthCredential {
    private let localAci: Aci
    private let redemptionTime: UInt64
    private let serverParams: GenericServerPublicParams
    private let authCredential: LibSignalClient.CallLinkAuthCredential

    init(
        localAci: Aci,
        redemptionTime: UInt64,
        serverParams: GenericServerPublicParams,
        authCredential: LibSignalClient.CallLinkAuthCredential
    ) {
        self.localAci = localAci
        self.redemptionTime = redemptionTime
        self.serverParams = serverParams
        self.authCredential = authCredential
    }

    public func present(callLinkParams: CallLinkSecretParams) -> CallLinkAuthCredentialPresentation {
        return self.authCredential.present(
            userId: self.localAci,
            redemptionTime: Date(timeIntervalSince1970: TimeInterval(self.redemptionTime)),
            serverParams: self.serverParams,
            callLinkParams: callLinkParams
        )
    }
}
