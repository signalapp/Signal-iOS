//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalRingRTC
import SignalServiceKit

public class GroupCallPeekClient: Dependencies {
    private var sfuUrl: String {
        DebugFlags.callingUseTestSFU.get() ? TSConstants.sfuTestURL : TSConstants.sfuURL
    }

    private let logger = PrefixedLogger(prefix: "GCPeek")

    let httpClient: SignalRingRTC.HTTPClient
    private let sfuClient: SignalRingRTC.SFUClient

    public init() {
        httpClient = SignalRingRTC.HTTPClient(delegate: nil)
        sfuClient = SFUClient(httpClient: httpClient)

        httpClient.delegate = self
    }

    /// Fetch the current group call peek info for the given thread.
    public func fetchPeekInfo(groupThread: TSGroupThread) -> Promise<PeekInfo> {
        AssertNotOnMainThread()

        return firstly { () -> Promise<Data> in
            self.fetchGroupMembershipProof(groupThread: groupThread)
        }.then(on: DispatchQueue.main) { (membershipProof: Data) -> Guarantee<PeekResponse> in
            let membership = try self.databaseStorage.read { tx in
                try self.groupMemberInfo(groupThread: groupThread, tx: tx)
            }

            let peekRequest = PeekRequest(
                sfuURL: self.sfuUrl,
                membershipProof: membershipProof,
                groupMembers: membership
            )

            return self.sfuClient.peek(request: peekRequest)
        }.map(on: DispatchQueue.sharedUtility) { peekResponse in
            if let errorCode = peekResponse.errorStatusCode {
                throw OWSGenericError("Failed to peek with status code: \(errorCode)")
            } else {
                return peekResponse.peekInfo
            }
        }
    }

    /// Fetches a data blob that serves as proof of membership in the group.
    /// Used by RingRTC to verify access to group call information.
    public func fetchGroupMembershipProof(groupThread: TSGroupThread) -> Promise<Data> {
        guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
            return Promise(error: OWSAssertionError("Expected V2 group model!"))
        }

        return firstly {
            try groupsV2Impl.fetchGroupExternalCredentials(groupModel: groupModel)
        }.map(on: DispatchQueue.sharedUtility) { (credential) -> Data in
            guard let tokenData = credential.token?.data(using: .utf8) else {
                throw OWSAssertionError("Invalid credential")
            }

            return tokenData
        }
    }

    public func groupMemberInfo(
        groupThread: TSGroupThread,
        tx: SDSAnyReadTransaction
    ) throws -> [GroupMemberInfo] {
        // Make sure we're working with the latest group state.
        groupThread.anyReload(transaction: tx)

        guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
            throw OWSAssertionError("Expected V2 group model!")
        }

        let groupV2Params = try groupModel.groupV2Params()

        return groupThread.groupMembership.fullMembers.compactMap {
            guard let aci = $0.serviceId as? Aci else {
                owsFailDebug("Skipping group member, missing uuid")
                return nil
            }

            guard let aciCiphertext = try? groupV2Params.userId(for: aci) else {
                owsFailDebug("Skipping group member, missing uuidCipherText")
                return nil
            }

            return GroupMemberInfo(
                userId: aci.rawUUID,
                userIdCipherText: aciCiphertext
            )
        }
    }
}

// MARK: - HTTPDelegate

extension GroupCallPeekClient: HTTPDelegate {
    /**
     * A HTTP request should be sent to the given url.
     * Invoked on the main thread, asychronously.
     * The result of the call should be indicated by calling the receivedHttpResponse() function.
     */
    public func sendRequest(requestId: UInt32, request: HTTPRequest) {
        AssertIsOnMainThread()
        logger.info("sendRequest")

        let session = OWSURLSession(
            securityPolicy: OWSURLSession.signalServiceSecurityPolicy,
            configuration: OWSURLSession.defaultConfigurationWithoutCaching,
            canUseSignalProxy: true
        )
        session.require2xxOr3xx = false
        session.allowRedirects = true
        session.customRedirectHandler = { redirectedRequest in
            var redirectedRequest = redirectedRequest
            if let authHeader = request.headers.first(where: {
                $0.key.caseInsensitiveCompare("Authorization") == .orderedSame
            }) {
                redirectedRequest.setValue(authHeader.value, forHTTPHeaderField: authHeader.key)
            }
            return redirectedRequest
        }

        firstly { () -> Promise<SignalServiceKit.HTTPResponse> in
            session.dataTaskPromise(
                request.url,
                method: request.method.httpMethod,
                headers: request.headers,
                body: request.body)

        }.done(on: DispatchQueue.main) { response in
            self.httpClient.receivedResponse(
                requestId: requestId,
                response: response.asRingRTCResponse
            )
        }.catch(on: DispatchQueue.main) { error in
            if error.isNetworkFailureOrTimeout {
                self.logger.warn("Peek client HTTP request had network error: \(error)")
            } else {
                owsFailDebug("Peek client HTTP request failed \(error)")
            }

            self.httpClient.httpRequestFailed(requestId: requestId)
        }
    }
}

extension SignalRingRTC.HTTPMethod {
    var httpMethod: SignalServiceKit.HTTPMethod {
        switch self {
        case .get: return .get
        case .post: return .post
        case .put: return .put
        case .delete: return .delete
        }
    }
}

extension SignalServiceKit.HTTPResponse {
    var asRingRTCResponse: SignalRingRTC.HTTPResponse {
        return SignalRingRTC.HTTPResponse(
            statusCode: UInt16(responseStatusCode),
            body: responseBodyData
        )
    }
}
