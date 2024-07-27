//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalRingRTC
import SignalServiceKit

public class CallLinkFetcherImpl {
    private let sfuClient: SFUClient
    // Even though we never use this, we need to retain it to ensure
    // `sfuClient` continues to work properly.
    private let sfuClientHttpClient: AnyObject

    public init() {
        let httpClient = CallHTTPClient()
        self.sfuClient = SignalRingRTC.SFUClient(httpClient: httpClient.ringRtcHttpClient)
        self.sfuClientHttpClient = httpClient
    }

    public func readCallLink(
        _ rootKey: CallLinkRootKey,
        authCredential: SignalServiceKit.CallLinkAuthCredential
    ) async throws -> CallLinkState {
        let sfuUrl = DebugFlags.callingUseTestSFU.get() ? TSConstants.sfuTestURL : TSConstants.sfuURL
        let secretParams = CallLinkSecretParams.deriveFromRootKey(rootKey.bytes)
        let authCredentialPresentation = authCredential.present(callLinkParams: secretParams)
        return CallLinkState(try await self.sfuClient.readCallLink(
            sfuUrl: sfuUrl,
            authCredentialPresentation: authCredentialPresentation.serialize(),
            linkRootKey: rootKey
        ).unwrap())
    }
}

private struct SFUError: Error {
    let rawValue: UInt16
}

extension SFUResult {
    public func unwrap() throws -> Value {
        switch self {
        case .success(let value):
            return value
        case .failure(let errorCode):
            throw SFUError(rawValue: errorCode)
        }
    }
}
