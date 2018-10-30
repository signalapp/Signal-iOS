//
//  ThreadManager.swift
//  RelayServiceKit
//
//  Created by Mark Descalzo on 10/5/18.
//

import Foundation

// Manager to handle thead update notifications in background
@objc public class ThreadManager : NSObject {
    @objc public static let sharedManager = ThreadManager()

    @objc public override init() {
        super.init()
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(threadExpressionUpdated(notification:)),
                                               name: NSNotification.Name.TSThreadExpressionChanged,
                                               object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func threadExpressionUpdated(notification: Notification?) {
        Logger.debug("notification: \(String(describing: notification))")
        if (notification?.object is TSThread) {
            if let thread = notification?.object as? TSThread {
                self.validate(thread: thread)
            }
        }
    }
    
    @objc public func validate(thread: TSThread) {
        
        guard thread.universalExpression != nil else {
            Logger.debug("Aborting attept to validate thread with empty universal expression.")
            return
        }
        
        CCSMCommManager.asyncTagLookup(with: thread.universalExpression!, success: { lookupDict in
            //if lookupDict
            if let userIds:[String] = lookupDict["userids"] as? [String] {
                thread.participantIds = userIds

                NotificationCenter.default.post(name: NSNotification.Name(rawValue: FLRecipientsNeedRefreshNotification),
                                                object: nil,
                                                userInfo: [ "userIds" : userIds ])
            }
            if let pretty:String = lookupDict["pretty"] as? String {
                thread.prettyExpression = pretty
            }
            if let expression:String = lookupDict["universal"] as? String {
                thread.universalExpression = expression
            }
            if let monitorids:[String] = lookupDict["monitorids"] as? [String] {
                thread.monitorIds = NSCountedSet.init(array: monitorids)
            }
            
            thread.save()
            
        }, failure: { error in
            Logger.debug("\(self.logTag): TagMath query for expression failed.  Error: \(error.localizedDescription)")
        })
    }
    

}
