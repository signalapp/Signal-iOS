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
    var avatarCache: NSCache = {
        let aCache = NSCache()
        aCache.delegate = self;
        return aCache
    }()

    private let readConnection: YapDatabaseConnection = { return OWSPrimaryStorage.shared().dbReadConnection }()
    private let readWriteConnection: YapDatabaseConnection = { return OWSPrimaryStorage.shared().dbReadWriteConnection }()
    private var prefs: PropertyListPreferences?
    private var latestRecipientsById: [AnyHashable : Any] = [:]
    private var activeRecipientsBacker: [SignalRecipient] = []
    private var visibleRecipientsPredicate: NSCompoundPredicate?
    private let recipientCache: NSCache = {
        let aCache = NSCache()
        aCache.delegate = self;
        return aCache
    }()
    private let tagCache: NSCache = {
        let aCache = NSCache()
        aCache.delegate = self;
        return aCache
    }()

    required init() {
        
        super.init()
        DispatchQueue.global(qos: .default).async(execute: {
            self.backgroundConnection.asyncRead(withBlock: { transaction in
                SignalRecipient.enumerateCollectionObjects(with: transaction, usingBlock: { object, stop in
                    var recipient = object as? SignalRecipient
                    self.recipientCache[recipient?.uniqueId] = recipient
                })
                FLTag.enumerateCollectionObjects(with: transaction, usingBlock: { object, stop in
                    var aTag = object as? FLTag
                    self.tagCache[aTag?.uniqueId] = aTag
                })
            })
        })
        NotificationCenter.default.addObserver(self, selector: #selector(self.processUsersBlob), name: FLCCSMUsersUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.processTagsBlob), name: FLCCSMTagsUpdated, object: nil)

    }
    
    func selfRecipient() -> RelayRecipient {
        var RelayRecipient = self.recipientCache.object
//        var RelayRecipient = self.recipient(userId: TSAccountManager.sharedInstance.localUID)
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
    }
    
    func recipient(withUserId userId: String, transaction: YapDatabaseReadWriteTransaction) -> RelayRecipient? {
    }
    
    func refreshCCSMRecipients() {
    }
    
    func image(forRecipientId uid: String) -> UIImage? {
    }
    
    func nameString(forContactId uid: String) -> String? {
    }
    
    func save(_ recipient: RelayRecipient) {
    }
    
    func save(_ recipient: RelayRecipient, with transaction: YapDatabaseReadWriteTransaction) {
    }
    
    func remove(_ recipient: RelayRecipient) {
    }
    
    func remove(_ recipient: RelayRecipient, with transaction: YapDatabaseReadWriteTransaction) {
    }
    
    func save(_ recipient: FLTag) {
    }
    
    func save(_ recipient: FLTag, with transaction: YapDatabaseReadWriteTransaction) {
    }
    
    func remove(_ recipient: FLTag) {
    }
    
    func remove(_ recipient: FLTag, with transaction: YapDatabaseReadWriteTransaction) {
    }
    
    func nukeAndPave() {
    }
}
