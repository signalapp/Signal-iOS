//
//  FLContactsManager.swift
//  RelayMessaging
//
//  Created by Mark Descalzo on 8/14/18.
//  Copyright © 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import YapDatabase
import RelayServiceKit

@objc public class FLContactsManager: NSObject, NSCacheDelegate {
    
    @objc public static let shared = FLContactsManager()
    
    @objc public var allRecipients: [RelayRecipient] = []
    @objc public var activeRecipients: [RelayRecipient] = []
    
    private let avatarCache: NSCache<NSString, UIImage>

    private let readConnection: YapDatabaseConnection = { return OWSPrimaryStorage.shared().dbReadConnection }()
    private let readWriteConnection: YapDatabaseConnection = { return OWSPrimaryStorage.shared().dbReadWriteConnection }()
    private var latestRecipientsById: [AnyHashable : Any] = [:]
    private var activeRecipientsBacker: [SignalRecipient] = []
    private var visibleRecipientsPredicate: NSCompoundPredicate?
    
    private let recipientCache: NSCache<NSString, RelayRecipient>
    private let tagCache: NSCache<NSString, FLTag>

    // TODO: require for gravatar implementation
//    private var prefs: PropertyListPreferences?

    required override public init() {
        
        avatarCache = NSCache<NSString, UIImage>()
        avatarCache.delegate = self
        recipientCache = NSCache<NSString, RelayRecipient>()
        recipientCache.delegate = self
        tagCache = NSCache<NSString, FLTag>()
        tagCache.delegate = self
        
        super.init()
        
        // Prepopulate the caches?
//        DispatchQueue.global(qos: .default).async(execute: {
//            self.readConnection.asyncRead({ transaction in
//                RelayRecipient.enumerateCollectionObjects(with: transaction, using: { object, stop in
//                    if let recipient = object as? RelayRecipient {
//                        self.recipientCache.setObject(recipient, forKey: recipient.uniqueId! as NSString)
//                    }
//                })
//                FLTag.enumerateCollectionObjects(with: transaction, using: { object, stop in
//                    if let aTag = object as? FLTag {
//                        self.tagCache.setObject(aTag, forKey: aTag.uniqueId! as NSString)
//                    }
//                })
//            })
//        })
        NotificationCenter.default.addObserver(self, selector: #selector(self.processRecipientsBlob), name: NSNotification.Name(rawValue: FLCCSMUsersUpdated), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.processTagsBlob), name: NSNotification.Name(rawValue: FLCCSMTagsUpdated), object: nil)

    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc public func selfRecipient() -> RelayRecipient {
        let selfId = TSAccountManager.localUID()! as NSString
        var recipient:RelayRecipient? = recipientCache.object(forKey: selfId)
        
        if recipient == nil {
            recipient = RelayRecipient.fetch(uniqueId: selfId as String)
            recipientCache .setObject(recipient!, forKey: selfId)
        }
        return recipient!
    }
    
    @objc public class func recipientComparator() -> Comparator {
    }
    
    @objc public func getObservableContacts() -> ObservableValue? {
    }
    
    @objc public func doAfterEnvironmentInitSetup() {
    }
    
    @objc public func updateRecipient(_ userId: String) {
    }
    
    @objc public func updateRecipient(_ userId: String, with transaction: YapDatabaseReadWriteTransaction) {
    }
    
    @objc public func recipient(withId userId: String) -> RelayRecipient? {
        var recipient:RelayRecipient? = recipientCache.object(forKey: userId as NSString)
        
        if recipient == nil {
            recipient = RelayRecipient.fetch(uniqueId: userId as String)
            recipientCache.setObject(recipient!, forKey: userId as NSString)
        }
        return recipient!
    }
    
    @objc public func recipient(withId userId: String, transaction: YapDatabaseReadWriteTransaction) -> RelayRecipient? {
        var recipient:RelayRecipient? = recipientCache.object(forKey: userId as NSString)
        
        if recipient == nil {
            recipient = RelayRecipient.fetch(uniqueId: userId, transaction: transaction)
            recipientCache.setObject(recipient!, forKey: userId as NSString)
        }
        return recipient!
        
    }
    
    @objc public func refreshCCSMRecipients() {
    }
    
    @objc public func image(forRecipientId uid: String) -> UIImage? {
        // TODO: implement gravatars here
        var image: UIImage? = nil
        var cacheKey: NSString? = nil
        
        // if using gravatars
        // cacheKey = "gravatar:\(uid)"
        // else
        cacheKey = "avatar:\(uid)" as NSString
        image = self.avatarCache.object(forKey: cacheKey!)
        
        if image == nil {
            image = self.recipient(withId: uid)?.avatar
            if image != nil {
                self.avatarCache.setObject(image!, forKey: cacheKey!)
            }
        }
        return image
    }
    
    @objc public func nameString(forRecipientId uid: String) -> String? {
        if let recipient:RelayRecipient = self.recipient(withId: uid) {
            if recipient.fullName().count > 0 {
                return recipient.fullName()
            } else if (recipient.flTag?.displaySlug.count)! > 0 {
                return recipient.flTag?.displaySlug
            }
        }
        return NSLocalizedString("UNKNOWN_CONTACT_NAME", comment: "Displayed if for some reason we can't determine a contacts ID *or* name");
    }
    
    // MARK: - Recipient management
    @objc public func processRecipientsBlob() {
        let recipientsBlob: NSDictionary = CCSMStorage.sharedInstance().getUsers()! as NSDictionary
        DispatchQueue.global(qos: .background).async {
            for recipientDict in recipientsBlob.allValues {
                self.readWriteConnection.asyncReadWrite({ (transaction) in
                    if let recipient: RelayRecipient = RelayRecipient.getOrCreateRecipient(withUserDictionary: recipientDict as! NSDictionary, transaction: transaction) {
                        self.save(recipient: recipient, with: transaction)
                    }
                })
            }
        }
    }

    @objc public func save(recipient: RelayRecipient) {
        self.readWriteConnection .readWrite { (transaction) in
            self.save(recipient: recipient, with: transaction)
        }
    }
    
    @objc public func save(recipient: RelayRecipient, with transaction: YapDatabaseReadWriteTransaction) {
        recipient.save(with: transaction)
        self.recipientCache.setObject(recipient, forKey: recipient.uniqueId! as NSString)
    }
    
    @objc public func remove(recipient: RelayRecipient) {
        self.readWriteConnection .readWrite { (transaction) in
            self.remove(recipient: recipient, with: transaction)
        }
    }
    
    @objc public func remove(recipient: RelayRecipient, with transaction: YapDatabaseReadWriteTransaction) {
        self.recipientCache.removeObject(forKey: recipient.uniqueId! as NSString)
        recipient.remove(with: transaction)
    }
    
    // MARK: - Tag management
    @objc public func processTagsBlob() {
        let tagsBlob: NSDictionary = CCSMStorage.sharedInstance().getTags()! as NSDictionary
        DispatchQueue.global(qos: .background).async {
            for tagDict in tagsBlob.allValues {
                self.readWriteConnection.asyncReadWrite({ (transaction) in
                    let aTag:FLTag = FLTag.getOrCreateTag(with: tagDict as! [AnyHashable : Any], transaction: transaction)!
                    if aTag.recipientIds?.count == 0 {
                        self.remove(tag: aTag, with: transaction)
                    } else {
                        self.save(tag: aTag, with: transaction)
                    }
                })
            }
        }
    }

    @objc public func save(tag: FLTag) {
        self.readWriteConnection.readWrite { (transaction) in
            self.save(tag: tag, with: transaction)
        }
    }
    
    @objc public func save(tag: FLTag, with transaction: YapDatabaseReadWriteTransaction) {
        tag.save(with: transaction)
        self.tagCache.setObject(tag, forKey: tag.uniqueId! as NSString)
    }
    
    @objc public func remove(tag: FLTag) {
        self.readWriteConnection.readWrite { (transaction) in
            self.remove(tag: tag, with: transaction)
        }
    }
    
    @objc public func remove(tag: FLTag, with transaction: YapDatabaseReadWriteTransaction) {
        self.tagCache.removeObject(forKey: tag.uniqueId! as NSString)
        tag.remove(with: transaction)
    }
    

    @objc func nukeAndPave() {
        self.tagCache.removeAllObjects()
        self.recipientCache.removeAllObjects()
        RelayRecipient.removeAllObjectsInCollection()
        FLTag.removeAllObjectsInCollection()
    }
    
    // MARK: - Helpers
}



//extension FLContactsManager : NSCacheDelegate {
//
//}
