//
//  ThreadManager.swift
//  RelayServiceKit
//
//  Created by Mark Descalzo on 10/5/18.
//

// TODO: Merge functionality with ThreadUtil?

import Foundation

// Manager to handle thead update notifications in background
@objc public class ThreadManager : NSObject {
    
    // Shared singleton
    @objc public static let sharedManager = ThreadManager()

    fileprivate let imageCache = NSCache<NSString, UIImage>()
    
    @objc public override init() {
        super.init()
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(threadExpressionUpdated(notification:)),
                                               name: NSNotification.Name.TSThreadExpressionChanged,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(yapDatabaseModified),
                                               name: NSNotification.Name.YapDatabaseModified,
                                               object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc public func image(threadId: String) -> UIImage? {
        if let image = self.imageCache.object(forKey: threadId as NSString) {
            return image
        } else {
            if let thread = TSThread.fetch(uniqueId: threadId) {
                if let image = thread.image {
                    // thread has assigned image
                    self.imageCache.setObject(image, forKey: threadId as NSString)
                    return image
                } else if thread.isOneOnOne {
                    // one-on-one, use other avatar
                    if let image = TextSecureKitEnv.shared().contactsManager.avatarImageRecipientId(thread.otherParticipantId!) {
                        self.imageCache.setObject(image, forKey: threadId as NSString)
                        return image
                    }
                }
                
            }
        }
        // Return default avatar
        return UIImage.init(named:"empty-group-avatar-gray");
    }
    
    @objc public func flushImageCache() {
        imageCache.removeAllObjects()
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
    
//    // MARK: - KVO
//    @objc override public func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
//        if keyPath == "useGravatars" {
//            for obj in TSThread.allObjectsInCollection() {
//                let thread = obj as! TSThread
//                thread.touch()
//            }
//        }
//    }
    
    // MARK: - db modifications
    private let readConnection: YapDatabaseConnection = OWSPrimaryStorage.shared().newDatabaseConnection()

    @objc func yapDatabaseModified(notification: Notification?) {
        
        DispatchQueue.global(qos: .background).async {
            let notifications = self.readConnection.beginLongLivedReadTransaction()
            self.readConnection.enumerateChangedKeys(inCollection: TSThread.collection(),
                                                     in: notifications) { (threadId, stop) in
                                                        // Remove cached image
                                                        self.imageCache.removeObject(forKey: threadId as NSString)
            }
        }
    }


}
