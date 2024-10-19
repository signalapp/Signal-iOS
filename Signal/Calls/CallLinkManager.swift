//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalRingRTC
import SignalServiceKit
import SignalUI

protocol CallLinkManager {
    /// - Returns: An era ID.
    func peekCallLink(
        rootKey: CallLinkRootKey,
        authCredential: SignalServiceKit.CallLinkAuthCredential
    ) async throws -> String?

    func createCallLink(rootKey: CallLinkRootKey) async throws -> CallLinkManagerImpl.CreateResult

    func deleteCallLink(
        rootKey: CallLinkRootKey,
        adminPasskey: Data,
        authCredential: SignalServiceKit.CallLinkAuthCredential
    ) async throws

    func updateCallLinkName(
        _ name: String,
        rootKey: CallLinkRootKey,
        adminPasskey: Data,
        authCredential: SignalServiceKit.CallLinkAuthCredential
    ) async throws -> SignalServiceKit.CallLinkState

    func updateCallLinkRestrictions(
        requiresAdminApproval: Bool,
        rootKey: CallLinkRootKey,
        adminPasskey: Data,
        authCredential: SignalServiceKit.CallLinkAuthCredential
    ) async throws -> SignalServiceKit.CallLinkState
}

class CallLinkManagerImpl: CallLinkManager {
    private let networkManager: NetworkManager
    private let serverParams: GenericServerPublicParams
    private let sfuClient: SignalRingRTC.SFUClient
    // Even though we never use this, we need to retain it to ensure
    // `sfuClient` continues to work properly.
    private let sfuClientHttpClient: AnyObject
    private let tsAccountManager: any TSAccountManager

    init(
        networkManager: NetworkManager,
        serverParams: GenericServerPublicParams,
        tsAccountManager: any TSAccountManager
    ) {
        self.networkManager = networkManager
        self.serverParams = serverParams
        let httpClient = CallHTTPClient()
        self.sfuClient = SignalRingRTC.SFUClient(httpClient: httpClient.ringRtcHttpClient)
        self.sfuClientHttpClient = httpClient
        self.tsAccountManager = tsAccountManager
    }

    // MARK: - Peek Call Link

    enum PeekError: Error {
        case expired
        case invalid
        case other(UInt16)
    }

    func peekCallLink(
        rootKey: CallLinkRootKey,
        authCredential: SignalServiceKit.CallLinkAuthCredential
    ) async throws -> String? {
        let sfuUrl = DebugFlags.callingUseTestSFU.get() ? TSConstants.sfuTestURL : TSConstants.sfuURL
        let secretParams = CallLinkSecretParams.deriveFromRootKey(rootKey.bytes)
        let authCredentialPresentation = authCredential.present(callLinkParams: secretParams)
        let peekResult = await self.sfuClient.peek(
            sfuUrl: sfuUrl,
            authCredentialPresentation: authCredentialPresentation.serialize(),
            linkRootKey: rootKey
        )
        if let errorCode = peekResult.errorStatusCode {
            switch errorCode {
            case PeekInfo.expiredCallLinkStatus:
                throw PeekError.expired
            case PeekInfo.invalidCallLinkStatus:
                throw PeekError.invalid
            default:
                throw PeekError.other(errorCode)
            }
        }
        return peekResult.peekInfo.eraId
    }

    // MARK: - Create Call Link

    private struct CallLinkCreateAuthResponse: Decodable {
        var credential: Data
    }

    private func fetchCreateCredential(for roomId: Data, localAci: Aci) async throws -> CreateCallLinkCredential {
        let credentialRequestContext = CreateCallLinkCredentialRequestContext.forRoomId(roomId)
        let httpRequest = TSRequest(
            url: URL(string: "v1/call-link/create-auth")!,
            method: "POST",
            parameters: [
                "createCallLinkCredentialRequest": credentialRequestContext.getRequest().serialize().asData.base64EncodedString()
            ]
        )
        let httpResult = try await self.networkManager.asyncRequest(httpRequest, canUseWebSocket: true)
        guard httpResult.responseStatusCode == 200, let responseBodyData = httpResult.responseBodyData else {
            throw OWSGenericError("Couldn't handle successful result from the server.")
        }
        let httpResponse = try JSONDecoder().decode(CallLinkCreateAuthResponse.self, from: responseBodyData)
        let credentialResponse = try CreateCallLinkCredentialResponse(contents: [UInt8](httpResponse.credential))
        return try credentialRequestContext.receive(credentialResponse, userId: localAci, params: self.serverParams)
    }

    struct CreateResult {
        var adminPasskey: Data
        var callLinkState: SignalServiceKit.CallLinkState
    }

    func createCallLink(rootKey: CallLinkRootKey) async throws -> CreateResult {
        let roomId = rootKey.deriveRoomId()
        let localIdentifiers = self.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction!
        let sfuUrl = DebugFlags.callingUseTestSFU.get() ? TSConstants.sfuTestURL : TSConstants.sfuURL
        let secretParams = CallLinkSecretParams.deriveFromRootKey(rootKey.bytes)
        let createCredential = try await fetchCreateCredential(for: roomId, localAci: localIdentifiers.aci)
        let createCredentialPresentation = createCredential.present(roomId: roomId, userId: localIdentifiers.aci, serverParams: self.serverParams, callLinkParams: secretParams)
        let publicParams = secretParams.getPublicParams()
        let adminPasskey = CallLinkRootKey.generateAdminPasskey()
        let callLinkState = SignalServiceKit.CallLinkState(try await self.sfuClient.createCallLink(
            sfuUrl: sfuUrl,
            createCredentialPresentation: createCredentialPresentation.serialize(),
            linkRootKey: rootKey,
            adminPasskey: adminPasskey,
            callLinkPublicParams: publicParams.serialize(),
            restrictions: SignalServiceKit.CallLinkState.Constants.defaultRequiresAdminApproval ? .adminApproval : .none
        ).unwrap())
        return CreateResult(adminPasskey: adminPasskey, callLinkState: callLinkState)
    }

    func deleteCallLink(
        rootKey: CallLinkRootKey,
        adminPasskey: Data,
        authCredential: SignalServiceKit.CallLinkAuthCredential
    ) async throws {
        let sfuUrl = DebugFlags.callingUseTestSFU.get() ? TSConstants.sfuTestURL : TSConstants.sfuURL
        let secretParams = CallLinkSecretParams.deriveFromRootKey(rootKey.bytes)
        let authCredentialPresentation = authCredential.present(callLinkParams: secretParams)
        return try await self.sfuClient.deleteCallLink(
            sfuUrl: sfuUrl,
            authCredentialPresentation: authCredentialPresentation.serialize(),
            linkRootKey: rootKey,
            adminPasskey: adminPasskey
        ).unwrap()
    }

    func updateCallLinkName(
        _ name: String,
        rootKey: CallLinkRootKey,
        adminPasskey: Data,
        authCredential: SignalServiceKit.CallLinkAuthCredential
    ) async throws -> SignalServiceKit.CallLinkState {
        let sfuUrl = DebugFlags.callingUseTestSFU.get() ? TSConstants.sfuTestURL : TSConstants.sfuURL
        let secretParams = CallLinkSecretParams.deriveFromRootKey(rootKey.bytes)
        let authCredentialPresentation = authCredential.present(callLinkParams: secretParams)
        return SignalServiceKit.CallLinkState(try await self.sfuClient.updateCallLinkName(
            sfuUrl: sfuUrl,
            authCredentialPresentation: authCredentialPresentation.serialize(),
            linkRootKey: rootKey,
            adminPasskey: adminPasskey,
            newName: name
        ).unwrap())
    }

    func updateCallLinkRestrictions(
        requiresAdminApproval: Bool,
        rootKey: CallLinkRootKey,
        adminPasskey: Data,
        authCredential: SignalServiceKit.CallLinkAuthCredential
    ) async throws -> SignalServiceKit.CallLinkState {
        let sfuUrl = DebugFlags.callingUseTestSFU.get() ? TSConstants.sfuTestURL : TSConstants.sfuURL
        let secretParams = CallLinkSecretParams.deriveFromRootKey(rootKey.bytes)
        let authCredentialPresentation = authCredential.present(callLinkParams: secretParams)
        return SignalServiceKit.CallLinkState(try await self.sfuClient.updateCallLinkRestrictions(
            sfuUrl: sfuUrl,
            authCredentialPresentation: authCredentialPresentation.serialize(),
            linkRootKey: rootKey,
            adminPasskey: adminPasskey,
            restrictions: requiresAdminApproval ? .adminApproval : .none
        ).unwrap())
    }
}
