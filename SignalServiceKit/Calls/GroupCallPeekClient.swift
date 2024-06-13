//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalRingRTC

public class GroupCallPeekLogger: PrefixedLogger {
    public static let shared = GroupCallPeekLogger()

    private convenience init() {
        self.init(prefix: "GroupCallPeek")
    }
}

public class GroupCallPeekClient {
    private var sfuUrl: String {
        DebugFlags.callingUseTestSFU.get() ? TSConstants.sfuTestURL : TSConstants.sfuURL
    }

    private let logger = GroupCallPeekLogger.shared

    private let db: any DB
    private let groupsV2: any GroupsV2
    public let httpClient: HTTPClient
    private let sfuClient: SFUClient

    init(
        db: any DB,
        groupsV2: any GroupsV2
    ) {
        self.db = db
        self.groupsV2 = groupsV2
        self.httpClient = SignalRingRTC.HTTPClient(delegate: nil)
        self.sfuClient = SFUClient(httpClient: self.httpClient)
        self.httpClient.delegate = self
    }

    /// Fetch the current group call peek info for the given thread.
    @MainActor
    public func fetchPeekInfo(groupThread: TSGroupThread) async throws -> PeekInfo {
        let membershipProof = try await self.fetchGroupMembershipProof(groupThread: groupThread)

        let membership = try self.db.read { tx in
            try self.groupMemberInfo(groupThread: groupThread, tx: tx)
        }

        let peekRequest = PeekRequest(
            sfuURL: self.sfuUrl,
            membershipProof: membershipProof,
            groupMembers: membership
        )

        let peekResponse = await self.sfuClient.peek(request: peekRequest)
        if let errorCode = peekResponse.errorStatusCode {
            throw OWSGenericError("Failed to peek with status code: \(errorCode)")
        } else {
            return peekResponse.peekInfo
        }
    }

    /// Fetches a data blob that serves as proof of membership in the group.
    /// Used by RingRTC to verify access to group call information.
    public func fetchGroupMembershipProof(groupThread: TSGroupThread) async throws -> Data {
        guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
            throw OWSAssertionError("Expected V2 group model!")
        }

        let credential = try await self.groupsV2.fetchGroupExternalCredentials(groupModel: groupModel)

        guard let tokenData = credential.token?.data(using: .utf8) else {
            throw OWSAssertionError("Invalid credential")
        }

        return tokenData
    }

    public func groupMemberInfo(
        groupThread: TSGroupThread,
        tx: DBReadTransaction
    ) throws -> [GroupMemberInfo] {
        // Make sure we're working with the latest group state.
        groupThread.anyReload(transaction: SDSDB.shimOnlyBridge(tx))

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

        Task { @MainActor in
            do {
                let response = try await session.dataTaskPromise(
                    request.url,
                    method: request.method.httpMethod,
                    headers: request.headers,
                    body: request.body
                ).awaitable()
                self.httpClient.receivedResponse(
                    requestId: requestId,
                    response: response.asRingRTCResponse
                )
            } catch {
                if error.isNetworkFailureOrTimeout {
                    self.logger.warn("Peek client HTTP request had network error: \(error)")
                } else {
                    owsFailDebug("Peek client HTTP request failed \(error)")
                }
                self.httpClient.httpRequestFailed(requestId: requestId)
            }
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
