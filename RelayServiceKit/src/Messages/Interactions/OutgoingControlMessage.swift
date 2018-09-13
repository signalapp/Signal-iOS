//
//  OutgoingControlMessage.swift
//  Forsta
//
//  Created by Mark Descalzo on 6/22/18.
//  Copyright © 2018 Forsta. All rights reserved.
//

import UIKit

@objc public class OutgoingControlMessage: TSOutgoingMessage {
    
    @objc let controlMessageType: String

    @objc required public init(thread: TSThread, controlType: String) {

        self.controlMessageType = controlType
        
        super.init(outgoingMessageWithTimestamp: NSDate.ows_millisecondTimeStamp(),
                   in: thread,
                   messageBody: nil,
                   attachmentIds: [],
                   expiresInSeconds: 0,
                   expireStartedAt: 0,
                   isVoiceMessage: false,
                   quotedMessage: nil,
                   contactShare: nil)
        
        self.messageType = "control"
        self.body = FLCCSMJSONService.blob(from: self)
    }
    
    @objc required public init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc required public init(dictionary dictionaryValue: [AnyHashable : Any]!) throws {
        fatalError("init(dictionary:) has not been implemented")
    }
    
    @objc override public var plainTextBody: String?
    {
        get { return nil }
        set { }
    }

    @objc override public var attributedTextBody: NSAttributedString?
    {
        get { return nil }
        set { }
    }
    
    @objc override public func shouldBeSaved() -> Bool {
        return false
    }

//    @objc override public func save() {
//        return      // never save control messages
//    }
//
//    @objc override public func save(with transaction: YapDatabaseReadWriteTransaction) {
//        return      // never save control messages
//    }
}
