//
//  IncomingControlMessage.swift
//  Forsta
//
//  Created by Mark Descalzo on 6/22/18.
//  Copyright © 2018 Forsta. All rights reserved.
//

import UIKit

@objc public class IncomingControlMessage: TSIncomingMessage {
    
    @objc let controlMessageType: String
    @objc let attachmentPointers: Array<OWSSignalServiceProtosAttachmentPointer>?
    
    @objc required public init?(thread: TSThread,
                                author: String,
                                payload: NSDictionary,
                                attachments: Array<OWSSignalServiceProtosAttachmentPointer>?) {
        
        let messageType = payload.object(forKey: "messageType") as! String
        
        if (messageType.count == 0) {
            Logger.error("Attempted to create control message with invalid payload.");
            return nil
        }
        
        let dataBlob = payload.object(forKey: "data") as! NSDictionary
        if dataBlob.allKeys.count == 0 {
            Logger.error("Attempted to create control message without data object.")
            return nil
        }
        
        let controlType = dataBlob.object(forKey: "control") as! String
        if controlType.count == 0 {
            Logger.error("Attempted to create control message without a type.")
            return nil
        }
        
        self.attachmentPointers = attachments
        self.controlMessageType = dataBlob.object(forKey: "control") as! String
        
        var attachmentIds:[String] = []
        if ((dataBlob.object(forKey: "attachments")) != nil) {
            attachmentIds = dataBlob.object(forKey: "attachments") as! [String]
        }

        super.init(incomingMessageWithTimestamp: NSDate.ows_millisecondTimeStamp(),
                   in: thread,
                   authorId: author,
                   sourceDeviceId: OWSDeviceManager.shared().currentDeviceId(),
                   messageBody: nil,
                   attachmentIds: attachmentIds,
                   expiresInSeconds: 0,
                   quotedMessage: nil,
                   contactShare: nil)
                
        self.messageType = "control"
        self.forstaPayload = payload.mutableCopy() as! NSMutableDictionary
    }
    
    @objc required public init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc required public init(dictionary dictionaryValue: [AnyHashable : Any]!) throws {
        fatalError("init(dictionary:) has not been implemented")
    }
}
