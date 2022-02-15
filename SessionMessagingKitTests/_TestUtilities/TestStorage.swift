// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import Sodium

@testable import SessionMessagingKit

class TestStorage: SessionMessagingKitStorageProtocol, Mockable {
    // MARK: - Mockable
    
    enum DataKey: Hashable {
        case allV2OpenGroups
        case openGroupPublicKeys
        case userKeyPair
        case openGroup
        case openGroupImage
        case openGroupUserCount
    }
    
    typealias Key = DataKey
    
    var mockData: [DataKey: Any] = [:]
    
    // MARK: - Shared

    @discardableResult func write(with block: @escaping (Any) -> Void) -> Promise<Void> {
        block(())   // TODO: Pass Transaction type to prevent force-cast crashes throughout codebase
        return Promise.value(())
    }
    
    @discardableResult func write(with block: @escaping (Any) -> Void, completion: @escaping () -> Void) -> Promise<Void> {
        block(())   // TODO: Pass Transaction type to prevent force-cast crashes throughout codebase
        return Promise.value(())
    }
    
    func writeSync(with block: @escaping (Any) -> Void) {
        block(())   // TODO: Pass Transaction type to prevent force-cast crashes throughout codebase
    }

    // MARK: - General

    func getUserPublicKey() -> String? { return nil }
    func getUserKeyPair() -> ECKeyPair? { return (mockData[.userKeyPair] as? ECKeyPair) }
    func getUserED25519KeyPair() -> Box.KeyPair? { return nil }
    func getUser() -> Contact? { return nil }
    func getAllContacts() -> Set<Contact> { return Set() }

    // MARK: - Closed Groups

    func getUserClosedGroupPublicKeys() -> Set<String> { return Set() }
    func getZombieMembers(for groupPublicKey: String) -> Set<String> { return Set() }
    func setZombieMembers(for groupPublicKey: String, to zombies: Set<String>, using transaction: Any) {}
    func isClosedGroup(_ publicKey: String) -> Bool { return false }

    // MARK: - Jobs

    func persist(_ job: Job, using transaction: Any) {}
    func markJobAsSucceeded(_ job: Job, using transaction: Any) {}
    func markJobAsFailed(_ job: Job, using transaction: Any) {}
    func getAllPendingJobs(of type: Job.Type) -> [Job] { return [] }
    func getAttachmentUploadJob(for attachmentID: String) -> AttachmentUploadJob? { return nil }
    func getMessageSendJob(for messageSendJobID: String) -> MessageSendJob? { return nil }
    func resumeMessageSendJobIfNeeded(_ messageSendJobID: String) {}
    func isJobCanceled(_ job: Job) -> Bool { return true }

    // MARK: - Authorization

    func getAuthToken(for room: String, on server: String) -> String? { return nil }
    func setAuthToken(for room: String, on server: String, to newValue: String, using transaction: Any) {}
    func removeAuthToken(for room: String, on server: String, using transaction: Any) {}

    // MARK: - Open Groups
    
    func getAllV2OpenGroups() -> [String: OpenGroupV2] { return (mockData[.allV2OpenGroups] as! [String: OpenGroupV2]) }
    func getV2OpenGroup(for threadID: String) -> OpenGroupV2? { return (mockData[.openGroup] as? OpenGroupV2) }
    func v2GetThreadID(for v2OpenGroupID: String) -> String? { return nil }
    func updateMessageIDCollectionByPruningMessagesWithIDs(_ messageIDs: Set<String>, using transaction: Any) {}
    
    // MARK: - Open Group Public Keys
    
    func getOpenGroupPublicKey(for server: String) -> String? {
        guard let publicKeyMap: [String: String] = mockData[.openGroupPublicKeys] as? [String: String] else {
            return (mockData[.openGroupPublicKeys] as? String)
        }
        
        return publicKeyMap[server]
    }
    
    func setOpenGroupPublicKey(for server: String, to newValue: String, using transaction: Any) {}

    // MARK: - Last Message Server ID

    func getLastMessageServerID(for room: String, on server: String) -> Int64? { return nil }
    func setLastMessageServerID(for room: String, on server: String, to newValue: Int64, using transaction: Any) {}
    func removeLastMessageServerID(for room: String, on server: String, using transaction: Any) {}

    // MARK: - Last Deletion Server ID

    func getLastDeletionServerID(for room: String, on server: String) -> Int64? { return nil }
    func setLastDeletionServerID(for room: String, on server: String, to newValue: Int64, using transaction: Any) {}
    func removeLastDeletionServerID(for room: String, on server: String, using transaction: Any) {}

    // MARK: - Message Handling

    func getReceivedMessageTimestamps(using transaction: Any) -> [UInt64] { return [] }
    func addReceivedMessageTimestamp(_ timestamp: UInt64, using transaction: Any) {}
    func getOrCreateThread(for publicKey: String, groupPublicKey: String?, openGroupID: String?, using transaction: Any) -> String? { return nil }
    func persist(_ message: VisibleMessage, quotedMessage: TSQuotedMessage?, linkPreview: OWSLinkPreview?, groupPublicKey: String?, openGroupID: String?, using transaction: Any) -> String? { return nil }
    func persist(_ attachments: [VisibleMessage.Attachment], using transaction: Any) -> [String] { return [] }
    func setAttachmentState(to state: TSAttachmentPointerState, for pointer: TSAttachmentPointer, associatedWith tsIncomingMessageID: String, using transaction: Any) {}
    func persist(_ stream: TSAttachmentStream, associatedWith tsIncomingMessageID: String, using transaction: Any) {}
}

// MARK: - SessionMessagingKitOpenGroupStorageProtocol

extension TestStorage: SessionMessagingKitOpenGroupStorageProtocol {
    func getOpenGroupImage(for room: String, on server: String) -> Data? { return (mockData[.openGroupImage] as? Data) }
    func setOpenGroupImage(to data: Data, for room: String, on server: String, using transaction: Any) {
        mockData[.openGroupImage] = data
    }
    
    func setV2OpenGroup(_ openGroup: OpenGroupV2, for threadID: String, using transaction: Any) {
        mockData[.openGroup] = openGroup
    }
    
    func getUserCount(forV2OpenGroupWithID openGroupID: String) -> UInt64? {
        return (mockData[.openGroupUserCount] as? UInt64)
    }
    
    func setUserCount(to newValue: UInt64, forV2OpenGroupWithID openGroupID: String, using transaction: Any) {
        mockData[.openGroupUserCount] = newValue
    }
}
