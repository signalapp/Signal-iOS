//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
public import SignalRingRTC

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
    private let sfuClient: SFUClient
    // Even though we never use this, we need to retain it to ensure
    // `sfuClient` continues to work properly.
    private let sfuClientHttpClient: AnyObject

    init(
        db: any DB,
        groupsV2: any GroupsV2
    ) {
        self.db = db
        self.groupsV2 = groupsV2
        let httpClient = CallHTTPClient()
        self.sfuClient = SignalRingRTC.SFUClient(httpClient: httpClient.ringRtcHttpClient)
        self.sfuClientHttpClient = httpClient
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
