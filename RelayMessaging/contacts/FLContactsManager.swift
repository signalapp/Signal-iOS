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

@objc public class FLContactsManager: NSObject, ContactsManagerProtocol {
    
    @objc public var isSystemContactsDenied: Bool = false // for future use
    
    public func cachedDisplayName(forRecipientId recipientId: String) -> String? {
        if let recipient:RelayRecipient = recipientCache.object(forKey: recipientId as NSString) {
            if recipient.fullName().count > 0 {
                return recipient.fullName()
            } else if (recipient.flTag?.displaySlug.count)! > 0 {
                return (recipient.flTag?.displaySlug)!
            }
        }
        return ""
    }
    
    public func displayName(forRecipientId recipientId: String) -> String? {
        if let recipient:RelayRecipient = self.recipient(withId: recipientId) {
            if recipient.fullName().count > 0 {
                return recipient.fullName()
            } else if (recipient.flTag?.displaySlug.count)! > 0 {
                return (recipient.flTag?.displaySlug)!
            }
        }
        return NSLocalizedString("UNKNOWN_CONTACT_NAME", comment: "Displayed if for some reason we can't determine a contacts ID *or* name");
    }
    
    public func isSystemContact(_ recipientId: String) -> Bool {
        // Placeholder for possible future use
        return false
    }
    
    public func isSystemContact(withRecipientId recipientId: String) -> Bool {
        // Placeholder for possible future use
        return false
    }
    
    public func compare(recipient left: RelayRecipient, with right: RelayRecipient) -> ComparisonResult {
        
        var comparisonResult: ComparisonResult = (left.lastName!.caseInsensitiveCompare(right.lastName!))
        
        if comparisonResult == .orderedSame {
            comparisonResult = (left.firstName!.caseInsensitiveCompare(right.firstName!))
            
            if comparisonResult == .orderedSame {
                comparisonResult = ((left.flTag!.slug.caseInsensitiveCompare(right.flTag!.slug)))
            }
        }
        return comparisonResult
    }
    
    public func avatarImageRecipientId(_ recipientId: String) -> UIImage? {

        var cacheKey: NSString? = nil
        
        if Environment.preferences().useGravatars() {
            cacheKey = "gravatar:\(recipientId)" as NSString
        } else {
            cacheKey = "avatar:\(recipientId)" as NSString
        }

        if let image = self.avatarCache.object(forKey: cacheKey!) {
            return image;
        } else {
            var image: UIImage?
            if Environment.preferences().useGravatars() {
                image = self.recipient(withId: recipientId)?.gravatarImage
            } else {
                image = self.recipient(withId: recipientId)?.avatarImage
            }
            return image
        }
    }
    
    
    @objc public static let shared = FLContactsManager()
    
//    @objc public var activeRecipients: [RelayRecipient] = []
    
    private let readConnection: YapDatabaseConnection = OWSPrimaryStorage.shared().newDatabaseConnection()
    private let readWriteConnection: YapDatabaseConnection = OWSPrimaryStorage.shared().newDatabaseConnection()
    private var latestRecipientsById: [AnyHashable : Any] = [:]
    private var activeRecipientsBacker: [ RelayRecipient ] = []
    private var visibleRecipientsPredicate: NSCompoundPredicate?
    
    private let avatarCache: NSCache<NSString, UIImage>
    private let recipientCache: NSCache<NSString, RelayRecipient>
    private let tagCache: NSCache<NSString, FLTag>
    
    @objc public func flushAvatarCache() {
        avatarCache.removeAllObjects()
    }

    override init() {
        avatarCache = NSCache<NSString, UIImage>()
        recipientCache = NSCache<NSString, RelayRecipient>()
        tagCache = NSCache<NSString, FLTag>()

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
        NotificationCenter.default.addObserver(self, selector: #selector(self.handleRecipientRefresh(notification:)), name: NSNotification.Name(rawValue: FLRecipientsNeedRefreshNotification), object: nil)


        avatarCache.delegate = self
        recipientCache.delegate = self
        tagCache.delegate = self
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc public func allRecipients() -> [RelayRecipient] {
        return RelayRecipient.allObjectsInCollection() as! [RelayRecipient]
    }

    
    @objc public func selfRecipient() -> RelayRecipient {
        let selfId = TSAccountManager.localUID()! as NSString
        var recipient:RelayRecipient? = recipientCache.object(forKey: selfId)
        
        if recipient == nil {
            recipient = RelayRecipient.fetch(uniqueId: selfId as String)
            recipientCache.setObject(recipient!, forKey: selfId)
        }
        return recipient!
    }
    
    @objc public class func recipientComparator() -> Comparator {
        return { obj1, obj2 in
            let contact1 = obj1 as? RelayRecipient
            let contact2 = obj2 as? RelayRecipient
            
            // Use lastname sorting
//            let firstNameOrdering = false // ABPersonGetSortOrdering() == kABPersonCompositeNameFormatFirstNameFirst ? YES : NO;
//
//            if firstNameOrdering {
//                return (contact1?.firstName.caseInsensitiveCompare(contact2?.firstName ?? ""))!
//            } else {
            return (contact1?.lastName!.caseInsensitiveCompare(contact2?.lastName ?? ""))!
//            }
        }    }
        
    @objc public func doAfterEnvironmentInitSetup() {
    }
    
    @objc public func handleRecipientRefresh(notification: Notification) {
        if let payloadArray: Array<String> = notification.userInfo!["userIds"] as? Array<String> {
            var lookupString: String = ""
            for uid: String in payloadArray {
                if UUID.init(uuidString: uid) != nil {
                    if lookupString.count == 0 {
                        lookupString = uid
                    } else {
                        lookupString.append(",\(uid)")
                    }
                }
            }
            if lookupString.count > 0 {
                DispatchQueue.global(qos: .background).async {
                    self.ccsmFetchRecipients(uids: lookupString)
                }
            }
        }
    }
    
    fileprivate func updateRecipients(userIds: Array<String>) {
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: FLRecipientsNeedRefreshNotification),
                                        object: self, userInfo: ["userIds" : userIds])
    }
    
    fileprivate func ccsmFetchRecipients(uids: String) {
        
        // must not execute on main thread
        assert(!Thread.isMainThread)
        
        let url = "\(CCSMEnvironment.sharedInstance().ccsmURLString!)/v1/directory/user/?id_in=\(uids)"
        
        CCSMCommManager.getThing(url,
                                 success: { (payload) in
                                    
                                    if let resultsArray: Array = payload?["results"] as? Array<Dictionary<String, Any>> {
                                        self.readWriteConnection .asyncReadWrite({ (transaction) in
                                            for userDict: Dictionary<String, Any> in resultsArray {
                                                if let recipient: RelayRecipient = self.recipient(fromDictionary: userDict, transaction: transaction){
                                                    recipient.save(with: transaction)
                                                }
                                            }
                                        })
                                    }
        }, failure: { (error) in
            Logger.debug("CCSM User lookup failed.")
        })
        
    }
    
    @objc public func tag(withId uuid: String) -> FLTag? {
        
        // Check the cache
        var atag:FLTag? = tagCache.object(forKey: uuid as NSString)
        
        // Check the db
        if atag == nil {
            self.readWriteConnection.read { (transaction) in
                atag = self.tag(withId: uuid, transaction: transaction)
                if atag != nil {
                    self.tagCache.setObject(atag!, forKey: atag?.uniqueId as! NSString);
                }
            }
        }
        return atag
    }
    
    @objc public func tag(withId uuid: String, transaction: YapDatabaseReadTransaction) -> FLTag? {
        
        // Check the cache
        if let atag:FLTag = tagCache.object(forKey: uuid as NSString) {
            return atag
        } else if let atag: FLTag = FLTag.fetch(uniqueId: uuid, transaction: transaction) {
            tagCache.setObject(atag, forKey: uuid as NSString)
            return atag
        } else {
            // TODO: Build notification path for tag updates
//            NotificationCenter.default.post(name: NSNotification.Name(rawValue: FLRecipientsNeedRefreshNotification),
//                                            object: self, userInfo: ["userIds" : [userId]])
        }
        return nil
    }


    
    @objc public func recipient(withId userId: String) -> RelayRecipient? {
        
        // Check the cache
        var recipient:RelayRecipient? = recipientCache.object(forKey: userId as NSString)
        
        // Check the db
        if recipient == nil {
            self.readWriteConnection.read { (transaction) in
                recipient = self.recipient(withId: userId, transaction: transaction)
                if recipient != nil {
                    self.recipientCache .setObject(recipient!, forKey: recipient?.uniqueId as! NSString);
                }
            }
        }
        return recipient
    }
    
    @objc public func recipient(withId userId: String, transaction: YapDatabaseReadTransaction) -> RelayRecipient? {

        // Check the cache
        if let recipient:RelayRecipient = recipientCache.object(forKey: userId as NSString) {
            return recipient
        } else if let recipient: RelayRecipient = RelayRecipient.fetch(uniqueId: userId, transaction: transaction) {
            recipientCache.setObject(recipient, forKey: userId as NSString)
            return recipient
        } else {
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: FLRecipientsNeedRefreshNotification),
                                            object: self, userInfo: ["userIds" : [userId]])
        }
        return nil
    }

    @objc public func recipient(fromDictionary userDict: Dictionary<String, Any>) -> RelayRecipient? {
        var recipient: RelayRecipient? = nil
        self.readWriteConnection.readWrite({ transaction in
            recipient = self.recipient(fromDictionary: userDict, transaction: transaction)
        })
        return recipient
    }
    
    func recipient(fromDictionary userDict: Dictionary<String, Any>, transaction: YapDatabaseReadWriteTransaction) -> RelayRecipient? {

        guard let uuid = NSUUID.init(uuidString:(userDict["id"] as? String)!) else {
           Logger.debug("Attempt to build recipient with malformed dictionary.")
            return nil
        }
        
        guard let tagDict = userDict["tag"] as? [AnyHashable : Any] else {
            Logger.debug("Missing tagDictionary for Recipient: \(uuid.uuidString)")
            return nil
        }

        let uidString = uuid.uuidString.lowercased()
        
        let recipient = RelayRecipient.getOrBuildUnsavedRecipient(forRecipientId: uidString, transaction: transaction)
        
        recipient.isActive = (Int(truncating: userDict["is_active"] as? NSNumber ?? 0)) == 1 ? true : false
        if !recipient.isActive {
            Logger.info("Removing inactive user: \(uidString)")
            self.remove(recipient: recipient, with: transaction)
            return nil
        }
        
        recipient.firstName = userDict["first_name"] as? String
        recipient.lastName = userDict["last_name"] as? String
        recipient.email = userDict["email"] as? String
        recipient.phoneNumber = userDict["phone"] as? String
        recipient.gravatarHash = userDict["gravatar_hash"] as? String
        recipient.isMonitor = (Int(truncating: userDict["is_monitor"] as? NSNumber ?? 0)) == 1 ? true : false
        
        let orgDict = userDict["org"] as? [AnyHashable : Any]
        if orgDict != nil {
            recipient.orgID = orgDict!["id"] as? String
            recipient.orgSlug = orgDict!["slug"] as? String
        } else {
            Logger.debug("Missing orgDictionary for Recipient: \(self.description)")
        }
        recipient.flTag = FLTag.getOrCreateTag(with: tagDict, transaction: transaction)
        recipient.flTag?.recipientIds = Set<AnyHashable>([recipient.uniqueId]) as? NSCountedSet
        if recipient.flTag?.tagDescription?.count == 0 {
            recipient.flTag?.tagDescription = recipient.fullName()
        }
        if recipient.flTag?.orgSlug.count == 0 {
            recipient.flTag?.orgSlug = recipient.orgSlug!
        }
        if recipient.flTag == nil {
            Logger.error("Attempt to create recipient with a nil tag!  Recipient: \(recipient.uniqueId)")
            self.remove(recipient: recipient, with: transaction)
            return nil
//        } else {
//            Logger.debug("Saving updated recipient: \(recipient.uniqueId)")
//            self.save(recipient: recipient, with: transaction)
        }
        
        return recipient
    }

    
    @objc public func refreshCCSMRecipients() {
        DispatchQueue.global(qos: .background).async {
            self.recipientCache.removeAllObjects()
            self.tagCache.removeAllObjects()
            CCSMCommManager.refreshCCSMData()
            self.validateNonOrgRecipients()
        }
    }
    
    private func validateNonOrgRecipients() {
        
        let nonOrgRecipients = RelayRecipient.allObjectsInCollection().filter() {
            if let recipient = ($0 as? RelayRecipient) {
                return (recipient.orgID != TSAccountManager.selfRecipient().orgID ||
                    recipient.orgID == "public" ||
                    recipient.orgID == "forsta" )
            } else {
                return false
            }
        }
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: FLRecipientsNeedRefreshNotification),
                                        object: self, userInfo: ["userIds" : nonOrgRecipients])
    }

    
    @objc public func setAvatarImage(image: UIImage, recipientId: String) {
        if let recipient = self.recipient(withId: recipientId) {
            recipient.avatarImage = image
            self.avatarCache.setObject(image, forKey: recipientId as NSString)
        }
    }
    
//    @objc public func image(forRecipientId uid: String) -> UIImage? {
//    }
    
//    @objc public func nameString(forRecipientId uid: String) -> String? {
//
//    }
    
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
        if let aTag = recipient.flTag {
            aTag.save(with: transaction)
        }
        self.recipientCache.setObject(recipient, forKey: recipient.uniqueId as NSString)
    }
    
    @objc public func remove(recipient: RelayRecipient) {
        self.readWriteConnection .readWrite { (transaction) in
            self.remove(recipient: recipient, with: transaction)
        }
    }
    
    @objc public func remove(recipient: RelayRecipient, with transaction: YapDatabaseReadWriteTransaction) {
        self.recipientCache.removeObject(forKey: recipient.uniqueId as NSString)
        if let aTag = recipient.flTag {
            aTag.remove(with: transaction)
        }
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
        self.tagCache.setObject(tag, forKey: tag.uniqueId as NSString)
    }
    
    @objc public func remove(tag: FLTag) {
        self.readWriteConnection.readWrite { (transaction) in
            self.remove(tag: tag, with: transaction)
        }
    }
    
    @objc public func remove(tag: FLTag, with transaction: YapDatabaseReadWriteTransaction) {
        self.tagCache.removeObject(forKey: tag.uniqueId as NSString)
        tag.remove(with: transaction)
    }
    

    @objc public func nukeAndPave() {
        self.tagCache.removeAllObjects()
        self.recipientCache.removeAllObjects()
        RelayRecipient.removeAllObjectsInCollection()
        FLTag.removeAllObjectsInCollection()
    }
    
    @objc public func supportsContactEditing() -> Bool {
        return false
    }
    
    @objc public func isSystemContactsAuthorized() -> Bool {
        return false
    }
    
    @objc public func formattedDisplayName(forTagId tagId: String, font: UIFont) -> NSAttributedString? {
        
        if let aTag = self.tag(withId:tagId) {
            let rawName = aTag.displaySlug
            
            let normalFontAttributes = [NSAttributedStringKey.font: font, NSAttributedStringKey.foregroundColor: Theme.primaryColor]
            
            let attrName = NSAttributedString(string: rawName, attributes: normalFontAttributes as [NSAttributedStringKey : Any])
            
            return attrName
        }
        return nil
    }

    
    @objc public func formattedFullName(forRecipientId recipientId: String, font: UIFont) -> NSAttributedString? {
        
        if let recipient = self.recipient(withId: recipientId) {
            let rawName = recipient.fullName()
            
            let normalFontAttributes = [NSAttributedStringKey.font: font, NSAttributedStringKey.foregroundColor: Theme.primaryColor]
            
            let attrName = NSAttributedString(string: rawName, attributes: normalFontAttributes as [NSAttributedStringKey : Any])

            return attrName
        }
        return nil
    }
    // MARK: - Helpers

}



extension FLContactsManager : NSCacheDelegate {

    public func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        // called when objects evicted from any of the caches
    }
}
