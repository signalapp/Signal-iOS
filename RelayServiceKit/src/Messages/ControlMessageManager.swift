//
//  ControlMessageManager.swift
//  Forsta
//
//  Created by Mark Descalzo on 6/22/18.
//  Copyright © 2018 Forsta. All rights reserved.
//

import Foundation

@objc
class ControlMessageManager : NSObject
{
    @objc static func processIncomingControlMessage(message: IncomingControlMessage, transaction: YapDatabaseReadWriteTransaction)
    {
        switch message.controlMessageType {
        case FLControlMessageSyncRequestKey:
            self.handleMessageSyncRequest(message: message, transaction: transaction)
        case FLControlMessageProvisionRequestKey:
            self.handleProvisionRequest(message: message, transaction: transaction)
        case FLControlMessageThreadUpdateKey:
            self.handleThreadUpdate(message: message, transaction: transaction)
        case FLControlMessageThreadClearKey:
            self.handleThreadClear(message: message, transaction: transaction)
        case FLControlMessageThreadCloseKey:
            self.handleThreadClose(message: message, transaction: transaction)
        case FLControlMessageThreadArchiveKey:
            self.handleThreadArchive(message: message, transaction: transaction)
        case FLControlMessageThreadRestoreKey:
            self.handleThreadRestore(message: message, transaction: transaction)
        case FLControlMessageThreadDeleteKey:
            self.handleThreadDelete(message: message, transaction: transaction)
        case FLControlMessageThreadSnoozeKey:
            self.handleThreadSnooze(message: message, transaction: transaction)
        case FLControlMessageCallOfferKey:
            self.handleCallOffer(message: message, transaction: transaction)
        case FLControlMessageCallAcceptOfferKey:
            self.handleCallAcceptOffer(message: message, transaction: transaction)
        case FLControlMessageCallLeaveKey:
            self.handleCallLeave(message: message, transaction: transaction)
        case FLControlMessageCallICECandidatesKey:
            self.handleCallICECandidates(message: message, transaction: transaction)
        default:
            Logger.info("Unhandled control message of type: \(message.controlMessageType)")
        }
    }
    
    static private func handleCallICECandidates(message: IncomingControlMessage, transaction: YapDatabaseReadWriteTransaction)
    {
        Logger.info("Received callICECandidates message: \(message.forstaPayload)")
        
        if let dataBlob = message.forstaPayload.object(forKey: "data") as? NSDictionary {
            
            let callId: String? = dataBlob.object(forKey: "callId") as? String
            
            guard callId != nil else {
                Logger.debug("Received callICECandidates message with no callId.")
                return
            }
            
            if let icecandidates: NSArray = dataBlob.object(forKey: "icecandidates") as? NSArray {
                for candidate in icecandidates as NSArray {
                    if let candidateDictiontary: Dictionary<String, Any> = candidate as? Dictionary<String, Any> {
                        if let sdpMLineIndex: Int32 = candidateDictiontary["sdpMLineIndex"] as? Int32,
                            let sdpMid: String = candidateDictiontary["sdpMid"] as? String,
                            let sdp: String = candidateDictiontary["candidate"] as? String {
                            
                            DispatchQueue.main.async {
                                TextSecureKitEnv.shared().callMessageHandler.receivedIceUpdate(withThreadId: callId!,
                                                                                               sessionDescription: sdp,
                                                                                               sdpMid: sdpMid,
                                                                                               sdpMLineIndex: sdpMLineIndex)
                            }
                        }
                    }
                }
            }
            
//            if let members = dataBlob.object(forKey: "members") {
//                Logger.info("members: \(members)")
//            }
//            if let originator = dataBlob.object(forKey: "originator") {
//                Logger.info("originator: \(originator)")
//            }
//            if let peerId = dataBlob.object(forKey: "peerId") {
//                Logger.info("peerId: \(peerId)")
//            }
        }
    }
    
    static private func handleCallOffer(message: IncomingControlMessage, transaction: YapDatabaseReadWriteTransaction)
    {
        guard #available(iOS 10.0, *) else {
            Logger.info("\(self.tag): Ignoring callOffer controler message due to iOS version.")
            return
        }
        
        
        let dataBlob = message.forstaPayload.object(forKey: "data") as? NSDictionary
        
        guard dataBlob != nil else {
            Logger.info("Received callOffer message with no data object.")
            return
        }
        
        let callId = dataBlob?.object(forKey: "callId") as? String
        let members = dataBlob?.object(forKey: "members") as? NSArray
        let originator = dataBlob?.object(forKey: "originator") as? String
        let peerId = dataBlob?.object(forKey: "peerId") as? String
        let offer = dataBlob?.object(forKey: "offer") as? NSDictionary
        
        
        guard callId != nil && members != nil && originator != nil && peerId != nil && offer != nil else {
            Logger.debug("Received callOffer message missing required objects.")
            return
        }
        
        let sdpString = offer?.object(forKey: "sdp") as? String
        
        guard sdpString != nil else {
            Logger.debug("sdb string missing from call offer.")
            return
        }
        
        DispatchQueue.main.async {
            TextSecureKitEnv.shared().callMessageHandler.receivedOffer(withThreadId: callId!, originatorId: message.authorId, peerId: peerId!, sessionDescription: sdpString!)
        }
    }
    
    static private func handleCallAcceptOffer(message: IncomingControlMessage, transaction: YapDatabaseReadWriteTransaction)
    {
        Logger.info("\(self.tag): Recieved Unimplemented control message type: \(message.controlMessageType)")
    }
    
    
    static private func handleCallLeave(message: IncomingControlMessage, transaction: YapDatabaseReadWriteTransaction)
    {
        //        Logger.info("Received callLeave message: \(message.forstaPayload)")
        // FIXME: Message processing stops while call is pending.

        let dataBlob = message.forstaPayload.object(forKey: "data") as? NSDictionary
        
        guard dataBlob != nil else {
            Logger.info("Received callLeave message with no data object.")
            return
        }
        
        let callId = dataBlob?.object(forKey: "callId") as? String
        
        guard callId != nil else {
            Logger.info("Received callLeave message without callId.")
            return
        }
        
        DispatchQueue.main.async {
            TextSecureKitEnv.shared().callMessageHandler.handleRemoteHangup(withCallId: callId!)
        }
    }
    
    static private func handleThreadUpdate(message: IncomingControlMessage, transaction: YapDatabaseReadWriteTransaction)
    {
        if let dataBlob = message.forstaPayload.object(forKey: "data") as? NSDictionary {
            if let threadUpdates = dataBlob.object(forKey: "threadUpdates") as? NSDictionary {
                
                let thread = message.thread
                let senderId = (message.forstaPayload.object(forKey: "sender") as! NSDictionary).object(forKey: "userId") as! String
                
                let sender = RelayRecipient.registeredRecipient(forRecipientId: senderId, transaction: transaction)
                
                // Handle thread name change
                if let threadTitle = threadUpdates.object(forKey: FLThreadTitleKey) as? String {
                    if thread.title != threadTitle {
                        thread.title = threadTitle
                        
                        var customMessage: String? = nil
                        var infoMessage: TSInfoMessage? = nil
                        
                        if sender != nil {
                            let format = NSLocalizedString("THREAD_TITLE_UPDATE_MESSAGE", comment: "") as NSString
                            customMessage = NSString.init(format: format as NSString, (sender?.fullName)!()) as String
                            
                            infoMessage = TSInfoMessage.init(timestamp: message.timestamp,
                                                             in: thread,
                                                             infoMessageType: TSInfoMessageType.typeConversationUpdate,
                                                             customMessage: customMessage!)
                            
                        } else {
                            infoMessage = TSInfoMessage.init(timestamp: message.timestamp,
                                                             in: thread,
                                                             infoMessageType: TSInfoMessageType.typeConversationUpdate)
                        }
                        
                        infoMessage?.save(with: transaction)
                        thread.save(with: transaction)
                    }
                }
                
                // Handle change to participants
                if let expression = threadUpdates.object(forKey: FLExpressionKey) as? String {
                    if thread.universalExpression != expression {
                        
                        thread.universalExpression = expression
                        
                        NotificationCenter.default.post(name: NSNotification.Name.TSThreadExpressionChanged,
                                                        object: thread,
                                                        userInfo: nil)
                    }
                }
                
                // Handle change to avatar
                if ((message.attachmentPointers) != nil) {
                    if (message.attachmentPointers?.count)! > 0 {
                        var properties: Array<Dictionary<String, String>> = []
                        for pointer in message.attachmentPointers! {
                            properties.append(["name" : pointer.fileName ])
                        }
                        
                            let attachmentsProcessor = OWSAttachmentsProcessor.init(attachmentProtos: message.attachmentPointers!,
                                                                                    networkManager: TSNetworkManager.shared(),
                                                                                    transaction: transaction)
                            
                            if attachmentsProcessor.hasSupportedAttachments {
                                attachmentsProcessor.fetchAttachments(for: nil,
                                                                      transaction: transaction,
                                                                      success: { (attachmentStream) in
                                                                        OWSPrimaryStorage.shared().dbReadWriteConnection.asyncReadWrite({ (transaction) in
                                                                            thread.image = attachmentStream.image()
                                                                            thread.save(with: transaction)
                                                                            attachmentStream.remove(with: transaction)
                                                                            let formatString = NSLocalizedString("THREAD_IMAGE_CHANGED_MESSAGE", comment: "")
                                                                            var messageString: String? = nil
                                                                            if sender?.uniqueId == TSAccountManager.localUID() {
                                                                                messageString = String.localizedStringWithFormat(formatString, NSLocalizedString("YOU_STRING", comment: ""))
                                                                            } else {
                                                                                let nameString: String = ((sender != nil) ? (sender?.fullName())! as String : NSLocalizedString("UNKNOWN_CONTACT_NAME", comment: ""))
                                                                                messageString = String.localizedStringWithFormat(formatString, nameString)
                                                                            }
                                                                            let infoMessage = TSInfoMessage.init(timestamp: message.timestamp,
                                                                                                                 in: thread,
                                                                                                                 infoMessageType: TSInfoMessageType.typeConversationUpdate,
                                                                                                                 customMessage: messageString!)
                                                                            infoMessage.save(with: transaction)
                                                                        })
                                }) { (error) in
                                    Logger.error("\(self.tag): Failed to fetch attachments for avatar with error: \(error.localizedDescription)")
                                }
                            }
                        
                    }
                }
            }
        }
    }
    
    static private func handleThreadClear(message: IncomingControlMessage, transaction: YapDatabaseReadWriteTransaction)
    {
        Logger.info("\(self.tag): Recieved Unimplemented control message type: \(message.controlMessageType)")
    }
    
    static private func handleThreadClose(message: IncomingControlMessage, transaction: YapDatabaseReadWriteTransaction)
    {
        // Treat these as archive messages
        self.handleThreadArchive(message: message, transaction: transaction)
    }
    
    static private func handleThreadArchive(message: IncomingControlMessage, transaction: YapDatabaseReadWriteTransaction)
    {
        OWSPrimaryStorage.shared().dbReadWriteConnection.asyncReadWrite { transaction in
            let threadId = message.forstaPayload.object(forKey: FLThreadIDKey) as! String
            if let thread = TSThread.fetch(uniqueId: threadId) {
                thread.archiveThread(with: transaction, referenceDate: NSDate.ows_date(withMillisecondsSince1970: message.timestamp))
                Logger.debug("\(self.tag): Archived thread: \(String(describing: thread.uniqueId))")
            }
        }
    }
    
    static private func handleThreadRestore(message: IncomingControlMessage, transaction: YapDatabaseReadWriteTransaction)
    {
        OWSPrimaryStorage.shared().dbReadWriteConnection.asyncReadWrite { transaction in
            let threadId = message.forstaPayload.object(forKey: FLThreadIDKey) as! String
            if let thread = TSThread.fetch(uniqueId: threadId) {
                thread.unarchiveThread(with: transaction)
                Logger.debug("\(self.tag): Unarchived thread: \(String(describing: thread.uniqueId))")
            }
        }
    }
    
    static private func handleThreadDelete(message: IncomingControlMessage, transaction: YapDatabaseReadWriteTransaction)
    {
        Logger.info("\(self.tag): Recieved Unimplemented control message type: \(message.controlMessageType)")
    }
    
    static private func handleThreadSnooze(message: IncomingControlMessage, transaction: YapDatabaseReadWriteTransaction)
    {
        Logger.info("\(self.tag): Recieved Unimplemented control message type: \(message.controlMessageType)")
    }
    
    static private func handleProvisionRequest(message: IncomingControlMessage, transaction: YapDatabaseReadWriteTransaction)
    {
        if let senderId: String = (message.forstaPayload.object(forKey: "sender") as! NSDictionary).object(forKey: "userId") as? String,
            let dataBlob: Dictionary<String, Any?> = message.forstaPayload.object(forKey: "data") as? Dictionary<String, Any?> {
            
            if !(senderId == FLSupermanDevID || senderId == FLSupermanStageID || senderId == FLSupermanProdID){
                Logger.error("\(self.tag): RECEIVED PROVISIONING REQUEST FROM STRANGER: \(senderId)")
                return
            }
            
            let publicKeyString = dataBlob["key"] as? String
            let deviceUUID = dataBlob["uuid"] as? String
            
            if publicKeyString?.count == 0 || deviceUUID?.count == 0 {
                Logger.error("\(self.tag): Received malformed provisionRequest control message. Bad data payload.")
                return
            }
            FLDeviceRegistrationService.sharedInstance().provisionOtherDevice(withPublicKey: publicKeyString!, andUUID: deviceUUID!)
        } else {
            Logger.error("\(self.tag): Received malformed provisionRequest control message.")
        }
    }
    
    static private func handleMessageSyncRequest(message: IncomingControlMessage, transaction: YapDatabaseReadWriteTransaction)
    {
        Logger.info("\(self.tag): Recieved Unimplemented control message type: \(message.controlMessageType)")
    }
    
    // MARK: - Logging
    static public func tag() -> NSString
    {
        return "[\(self.classForCoder())]" as NSString
    }
    
}
