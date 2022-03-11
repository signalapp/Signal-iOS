// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import Sodium

@testable import SessionMessagingKit

class MockStorage: Mock<SessionMessagingKitStorageProtocol>, SessionMessagingKitStorageProtocol {
    // MARK: - Shared

    @discardableResult func write(with block: @escaping (Any) -> Void) -> Promise<Void> {
        return accept(args: [block]) as! Promise<Void>
    }
    
    @discardableResult func write(with block: @escaping (Any) -> Void, completion: @escaping () -> Void) -> Promise<Void> {
        return accept(args: [block, completion]) as! Promise<Void>
    }
    
    func writeSync(with block: @escaping (Any) -> Void) {
        accept(args: [block])
    }

    // MARK: - General

    func getUserPublicKey() -> String? { return accept() as? String }
    func getUserKeyPair() -> ECKeyPair? { return accept() as? ECKeyPair }
    func getUserED25519KeyPair() -> Box.KeyPair? { return accept() as? Box.KeyPair }
    func getUser() -> Contact? { return accept() as? Contact }
    func getAllContacts() -> Set<Contact> { return accept() as! Set<Contact> }
    func getAllContacts(with transaction: YapDatabaseReadTransaction) -> Set<Contact> { return accept() as! Set<Contact> }
    
    // MARK: - Blinded Id cache
    
    func getBlindedIdMapping(with blindedId: String) -> BlindedIdMapping? {
        return accept(args: [blindedId]) as? BlindedIdMapping
    }
    
    func getBlindedIdMapping(with blindedId: String, using transaction: YapDatabaseReadTransaction) -> BlindedIdMapping? {
        return accept(args: [blindedId, transaction]) as? BlindedIdMapping
    }
    
    func cacheBlindedIdMapping(_ mapping: BlindedIdMapping) { accept(args: [mapping]) }
    func cacheBlindedIdMapping(_ mapping: BlindedIdMapping, using transaction: YapDatabaseReadWriteTransaction) {
        accept(args: [mapping, transaction])
    }
    func enumerateBlindedIdMapping(with block: @escaping (BlindedIdMapping, UnsafeMutablePointer<ObjCBool>) -> ()) {
        accept(args: [block])
    }
    func enumerateBlindedIdMapping(using transaction: YapDatabaseReadTransaction, with block: @escaping (BlindedIdMapping, UnsafeMutablePointer<ObjCBool>) -> ()) {
        accept(args: [transaction, block])
    }

    // MARK: - Closed Groups

    func getUserClosedGroupPublicKeys() -> Set<String> { return accept() as! Set<String> }
    func getZombieMembers(for groupPublicKey: String) -> Set<String> { return accept() as! Set<String> }
    func setZombieMembers(for groupPublicKey: String, to zombies: Set<String>, using transaction: Any) {
        accept(args: [groupPublicKey, zombies, transaction])
    }
    func isClosedGroup(_ publicKey: String) -> Bool { return accept() as! Bool }

    // MARK: - Jobs

    func persist(_ job: Job, using transaction: Any) { accept(args: [job, transaction]) }
    func markJobAsSucceeded(_ job: Job, using transaction: Any) { accept(args: [job, transaction]) }
    func markJobAsFailed(_ job: Job, using transaction: Any) { accept(args: [job, transaction]) }
    func getAllPendingJobs(of type: Job.Type) -> [Job] {
        return accept(args: [type]) as! [Job]
    }
    func getAttachmentUploadJob(for attachmentID: String) -> AttachmentUploadJob? {
        return accept(args: [attachmentID]) as? AttachmentUploadJob
    }
    func getMessageSendJob(for messageSendJobID: String) -> MessageSendJob? {
        return accept(args: [messageSendJobID]) as? MessageSendJob
    }
    func getMessageSendJob(for messageSendJobID: String, using transaction: Any) -> MessageSendJob? {
        return accept(args: [messageSendJobID, transaction]) as? MessageSendJob
    }
    func resumeMessageSendJobIfNeeded(_ messageSendJobID: String) { accept(args: [messageSendJobID]) }
    func isJobCanceled(_ job: Job) -> Bool {
        return accept(args: [job]) as! Bool
    }

    // MARK: - Open Groups
    
    func getAllOpenGroups() -> [String: OpenGroup] { return accept() as! [String: OpenGroup] }
    func getThreadID(for v2OpenGroupID: String) -> String? { return accept(args: [v2OpenGroupID]) as? String }
    func updateMessageIDCollectionByPruningMessagesWithIDs(_ messageIDs: Set<String>, using transaction: Any) {
        accept(args: [messageIDs, transaction])
    }
    
    func getOpenGroupImage(for room: String, on server: String) -> Data? { return accept(args: [room, server]) as? Data }
    func setOpenGroupImage(to data: Data, for room: String, on server: String, using transaction: Any) {
        accept(args: [data, room, server, transaction])
    }
    
    func getOpenGroup(for threadID: String) -> OpenGroup? { return accept(args: [threadID]) as? OpenGroup }
    func setOpenGroup(_ openGroup: OpenGroup, for threadID: String, using transaction: Any) {
        accept(args: [openGroup, threadID, transaction])
    }
    func removeOpenGroup(for threadID: String, using transaction: Any) { accept(args: [threadID, transaction]) }
    func getOpenGroupServer(name: String) -> OpenGroupAPI.Server? { return accept(args: [name]) as? OpenGroupAPI.Server }
    func setOpenGroupServer(_ server: OpenGroupAPI.Server, using transaction: Any) { accept(args: [server, transaction]) }
    func removeOpenGroupServer(name: String, using transaction: Any) {
        accept(args: [name, transaction])
    }
    
    func getUserCount(forOpenGroupWithID openGroupID: String) -> UInt64? { return accept(args: [openGroupID]) as? UInt64 }
    func setUserCount(to newValue: UInt64, forOpenGroupWithID openGroupID: String, using transaction: Any) {
        accept(args: [newValue, openGroupID, transaction])
    }
    
    func getOpenGroupSequenceNumber(for room: String, on server: String) -> Int64? {
        return accept(args: [room, server]) as? Int64
    }
    func setOpenGroupSequenceNumber(for room: String, on server: String, to newValue: Int64, using transaction: Any) {
        accept(args: [room, server, newValue, transaction])
    }
    func removeOpenGroupSequenceNumber(for room: String, on server: String, using transaction: Any) {
        accept(args: [room, server, transaction])
    }

    func getOpenGroupInboxLatestMessageId(for server: String) -> Int64? { return accept(args: [server]) as? Int64 }
    func setOpenGroupInboxLatestMessageId(for server: String, to newValue: Int64, using transaction: Any) {
        accept(args: [server, newValue, transaction])
    }
    func removeOpenGroupInboxLatestMessageId(for server: String, using transaction: Any) { accept(args: [server, transaction]) }
    
    func getOpenGroupOutboxLatestMessageId(for server: String) -> Int64? { return accept(args: [server]) as? Int64 }
    func setOpenGroupOutboxLatestMessageId(for server: String, to newValue: Int64, using transaction: Any) {
        accept(args: [server, newValue, transaction])
    }
    func removeOpenGroupOutboxLatestMessageId(for server: String, using transaction: Any) {
        accept(args: [server, transaction])
    }
    
    // MARK: - Open Group Public Keys
    
    func getOpenGroupPublicKey(for server: String) -> String? { return accept(args: [server]) as? String }
    func setOpenGroupPublicKey(for server: String, to newValue: String, using transaction: Any) {
        accept(args: [server, newValue, transaction])
    }
    func removeOpenGroupPublicKey(for server: String, using transaction: Any) { accept(args: [server, transaction]) }

    // MARK: - Message Handling
    
    func getAllMessageRequestThreads() -> [String: TSContactThread] { return accept() as! [String: TSContactThread] }
    func getAllMessageRequestThreads(using transaction: YapDatabaseReadTransaction) -> [String: TSContactThread] {
        return accept(args: [transaction]) as! [String: TSContactThread]
    }

    func getReceivedMessageTimestamps(using transaction: Any) -> [UInt64] {
        return accept(args: [transaction]) as! [UInt64]
    }
    
    func removeReceivedMessageTimestamps(_ timestamps: Set<UInt64>, using transaction: Any) {
        accept(args: [timestamps, transaction])
    }
    func addReceivedMessageTimestamp(_ timestamp: UInt64, using transaction: Any) {
        accept(args: [timestamp, transaction])
    }
    
    func getOrCreateThread(for publicKey: String, groupPublicKey: String?, openGroupID: String?, using transaction: Any) -> String? {
        return accept(args: [publicKey, groupPublicKey, openGroupID, transaction]) as? String
    }
    func persist(_ message: VisibleMessage, quotedMessage: TSQuotedMessage?, linkPreview: OWSLinkPreview?, groupPublicKey: String?, openGroupID: String?, using transaction: Any) -> String? {
        return accept(args: [message, quotedMessage, linkPreview, groupPublicKey, openGroupID, transaction]) as? String
    }
    func persist(_ attachments: [VisibleMessage.Attachment], using transaction: Any) -> [String] {
        return accept(args: [attachments, transaction]) as! [String]
    }
    func setAttachmentState(to state: TSAttachmentPointerState, for pointer: TSAttachmentPointer, associatedWith tsIncomingMessageID: String, using transaction: Any) {
        accept(args: [state, pointer, tsIncomingMessageID, transaction])
    }
    func persist(_ stream: TSAttachmentStream, associatedWith tsIncomingMessageID: String, using transaction: Any) {
        accept(args: [stream, tsIncomingMessageID, transaction])
    }
}
