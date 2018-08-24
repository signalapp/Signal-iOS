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

class FLContactsManager: NSObject, NSCacheDelegate {
    
    public static let shared = FLContactsManager()
    
    var allRecipients: [RelayRecipient] = []
    var activeRecipients: [RelayRecipient] = []
    
    private let avatarCache: NSCache<NSString, UIImage>

    private let readConnection: YapDatabaseConnection = { return OWSPrimaryStorage.shared().dbReadConnection }()
    private let readWriteConnection: YapDatabaseConnection = { return OWSPrimaryStorage.shared().dbReadWriteConnection }()
    private var latestRecipientsById: [AnyHashable : Any] = [:]
    private var activeRecipientsBacker: [SignalRecipient] = []
    private var visibleRecipientsPredicate: NSCompoundPredicate?
    
    private let recipientCache: NSCache<NSString, RelayRecipient>
    private let tagCache: NSCache<NSString, FLTag>

    private var prefs: PropertyListPreferences?

    required override init() {
        
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
    
    func selfRecipient() -> RelayRecipient {
        let selfId = TSAccountManager.localUID()! as NSString
        var recipient:RelayRecipient? = recipientCache.object(forKey: selfId)
        
        if recipient == nil {
            recipient = RelayRecipient.fetch(uniqueId: selfId as String)
            recipientCache .setObject(recipient!, forKey: selfId)
        }
        return recipient!
    }
    
    class func recipientComparator() -> Comparator {
    }
    
    func getObservableContacts() -> ObservableValue? {
    }
    
    func doAfterEnvironmentInitSetup() {
    }
    
    func updateRecipient(_ userId: String) {
    }
    
    func updateRecipient(_ userId: String, with transaction: YapDatabaseReadWriteTransaction) {
    }
    
    func recipient(withUserId userId: String) -> RelayRecipient? {
        var recipient:RelayRecipient? = recipientCache.object(forKey: userId as NSString)
        
        if recipient == nil {
            recipient = RelayRecipient.fetch(uniqueId: userId as String)
            recipientCache.setObject(recipient!, forKey: userId as NSString)
        }
        return recipient!
    }
    
    func recipient(withUserId userId: String, transaction: YapDatabaseReadWriteTransaction) -> RelayRecipient? {
        var recipient:RelayRecipient? = recipientCache.object(forKey: userId as NSString)
        
        if recipient == nil {
            recipient = RelayRecipient.fetch(uniqueId: userId, transaction: transaction)
            recipientCache.setObject(recipient!, forKey: userId as NSString)
        }
        return recipient!
        
    }
    
    func refreshCCSMRecipients() {
    }
    
    func image(forRecipientId uid: String) -> UIImage? {
    }
    
    func nameString(forContactId uid: String) -> String? {
    }
    
    // MARK: - Recipient management
    @objc public func processRecipientsBlob() {
        let recipientsBlob: NSDictionary = CCSMStorage.sharedInstance().getUsers()! as NSDictionary
        DispatchQueue.global(qos: .background).async {
            for recipientDict in recipientsBlob.allValues {
                self.readWriteConnection.asyncReadWrite({ (transaction) in
                    if let recipient: RelayRecipient = RelayRecipient.getOrCreateRecipient(withUserDictionary: recipientDict as! NSDictionary, transaction: transaction) {
                        self.save(recipient, with: transaction)
                    }
                })
            }
        }
    }

    public func save(_ recipient: RelayRecipient) {
        self.readWriteConnection .readWrite { (transaction) in
            self.save(recipient, with: transaction)
        }
    }
    
    public func save(_ recipient: RelayRecipient, with transaction: YapDatabaseReadWriteTransaction) {
        recipient.save(with: transaction)
        self.recipientCache.setObject(recipient, forKey: recipient.uniqueId! as NSString)
    }
    
    public func remove(_ recipient: RelayRecipient) {
        self.readWriteConnection .readWrite { (transaction) in
            self.remove(recipient, with: transaction)
        }
    }
    
    public func remove(_ recipient: RelayRecipient, with transaction: YapDatabaseReadWriteTransaction) {
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
                        self.remove(aTag, with: transaction)
                    } else {
                        self.save(aTag, with: transaction)
                    }
                })
            }
        }
    }

    public func save(_ tag: FLTag) {
        self.readWriteConnection.readWrite { (transaction) in
            self.save(tag, with: transaction)
        }
    }
    
    public func save(_ tag: FLTag, with transaction: YapDatabaseReadWriteTransaction) {
        tag.save(with: transaction)
        self.tagCache.setObject(tag, forKey: tag.uniqueId! as NSString)
    }
    
    public func remove(_ tag: FLTag) {
        self.readWriteConnection.readWrite { (transaction) in
            self.remove(tag, with: transaction)
        }
    }
    
    public func remove(_ tag: FLTag, with transaction: YapDatabaseReadWriteTransaction) {
        self.tagCache.removeObject(forKey: tag.uniqueId! as NSString)
        tag.remove(with: transaction)
    }
    

    func nukeAndPave() {
        self.tagCache.removeAllObjects()
        self.recipientCache.removeAllObjects()
        RelayRecipient.removeAllObjectsInCollection()
        FLTag.removeAllObjectsInCollection()
    }
}

//extension FLContactsManager : NSCacheDelegate {
//
//}
