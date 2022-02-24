//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import SignalServiceKit
import SignalRingRTC

@objc
public class LightweightCallManager: NSObject, CallManagerLiteDelegate, Dependencies {

    public let managerLite: CallManagerLite
    private var sfuUrl: String { DebugFlags.callingUseTestSFU.get() ? TSConstants.sfuTestURL : TSConstants.sfuURL }

    public override init() {
        managerLite = CallManagerLite()
        super.init()
        managerLite.delegate = self
    }

    public func fetchPeekInfo(for thread: TSGroupThread) -> Promise<PeekInfo> {
        firstly {
            self.fetchGroupMembershipProof(for: thread)

        }.map { proof in
            let membership = try self.databaseStorage.read {
                try self.groupMemberInfo(for: thread, transaction: $0)
            }
            return (proof, membership)

        }.then { (proof, membership) in
            self.managerLite.peekGroupCall(sfuUrl: self.sfuUrl, membershipProof: proof, groupMembers: membership)
        }
    }


    public func fetchGroupMembershipProof(for thread: TSGroupThread) -> Promise<Data> {
        guard let groupModel = thread.groupModel as? TSGroupModelV2 else {
            owsFailDebug("unexpectedly missing group model")
            return Promise(error: OWSAssertionError("Invalid group"))
        }

        return firstly {
            try groupsV2Impl.fetchGroupExternalCredentials(groupModel: groupModel)
        }.map { (credential) -> Data in
            guard let tokenData = credential.token?.data(using: .utf8) else {
                throw OWSAssertionError("Invalid credential")
            }
            return tokenData
        }
    }

    /**
     * A HTTP request should be sent to the given url.
     * Invoked on the main thread, asychronously.
     * The result of the call should be indicated by calling the receivedHttpResponse() function.
     */
    public func callManagerLite(
        _ callManagerLite: CallManagerLite,
        shouldSendHttpRequest requestId: UInt32,
        url: String,
        method: CallManagerHttpMethod,
        headers: [String: String],
        body: Data?
    ) {
        AssertIsOnMainThread()
        Logger.info("shouldSendHttpRequest")

        let session = OWSURLSession(
            securityPolicy: OWSURLSession.signalServiceSecurityPolicy,
            configuration: OWSURLSession.defaultConfigurationWithoutCaching
        )
        session.require2xxOr3xx = false
        session.allowRedirects = true
        session.customRedirectHandler = { request in
            var request = request

            if let authHeader = headers.first(where: {
                $0.key.caseInsensitiveCompare("Authorization") == .orderedSame
            }) {
                request.addValue(authHeader.value, forHTTPHeaderField: authHeader.key)
            }

            return request
        }

        firstly(on: .sharedUtility) {
            session.dataTaskPromise(url, method: method.httpMethod, headers: headers, body: body)
        }.done(on: .main) { response in
            callManagerLite.receivedHttpResponse(
                requestId: requestId,
                statusCode: UInt16(response.responseStatusCode),
                body: response.responseBodyData
            )
        }.catch(on: .main) { error in
            if error.isNetworkFailureOrTimeout {
                Logger.warn("Call manager http request failed \(error)")
            } else {
                owsFailDebug("Call manager http request failed \(error)")
            }
            callManagerLite.httpRequestFailed(requestId: requestId)
        }
    }

    public func groupMemberInfo(for thread: TSGroupThread, transaction: SDSAnyReadTransaction) throws -> [GroupMemberInfo] {
        // Make sure we're working with the latest group state.
        thread.anyReload(transaction: transaction)

        guard let groupModel = thread.groupModel as? TSGroupModelV2 else {
            throw OWSAssertionError("Invalid group thread")
        }
        let groupV2Params = try groupModel.groupV2Params()

        return thread.groupMembership.fullMembers.compactMap {
            guard let uuid = $0.uuid else {
                owsFailDebug("Skipping group member, missing uuid")
                return nil
            }
            guard let uuidCipherText = try? groupV2Params.userId(forUuid: uuid) else {
                owsFailDebug("Skipping group member, missing uuidCipherText")
                return nil
            }

            return GroupMemberInfo(userId: uuid, userIdCipherText: uuidCipherText)
        }
    }
}

extension CallManagerHttpMethod {
    var httpMethod: HTTPMethod {
        switch self {
        case .get: return .get
        case .post: return .post
        case .put: return .put
        case .delete: return .delete
        }
    }
}
