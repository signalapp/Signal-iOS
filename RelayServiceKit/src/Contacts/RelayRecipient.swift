//
//  RelayRecipient.swift
//  RelayServiceKit
//
//  Created by Mark Descalzo on 8/14/18.
//

import Foundation
import YapDatabase

@objc
class RelayRecipient: TSYapDatabaseObject {
    
    // Forsta additions - departure from Contact usage
    @objc var firstName = ""
    @objc var lastName = ""
    @objc var phoneNumber = ""
    @objc var email = ""
    @objc var notes = ""
    @objc var flTag: FLTag?
    @objc var avatar: UIImage?
    @objc var orgSlug = ""
    @objc var orgID = ""
    @objc var gravatarHash = ""
    @objc var gravatarImage: UIImage?
    @objc var hiddenDate: Date?
    @objc var isMonitor = false
    @objc var isActive = false
    
    fileprivate(set) var devices: NSOrderedSet?

    func fullName() -> String {
        if firstName != "" && lastName != "" {
            return "\(firstName) \(lastName)"
        } else if lastName != "" {
            return lastName
        } else if firstName != "" {
            return firstName
        } else {
            return "No Name"
        }
    }
    
    class func registeredRecipient(forRecipientId recipientId: String, transaction: YapDatabaseReadTransaction?) -> RelayRecipient? {
        assert((recipientId.count) > 0)

        if transaction != nil {
            return RelayRecipient.fetch(uniqueId: recipientId, transaction: transaction!)
        } else {
            return RelayRecipient.fetch(uniqueId: recipientId)
        }
    }
    
    class func getOrCreateRecipient(withUserDictionary userDict: NSDictionary, transaction: YapDatabaseReadWriteTransaction) -> RelayRecipient? {

        if let uid = userDict["id"] as? String {
            
            let recipient: RelayRecipient = RelayRecipient.getOrBuildUnsavedRecipient(forRecipientId: uid, transaction: transaction)
            
            if userDict["is_active"] as! NSNumber == 0 {
                Logger.debug("\(self.logTag()) removing inactive user: \(uid)")
                recipient.remove(with: transaction)
                return nil
            } else {
                recipient.isActive = true
            }

            
            recipient.firstName = userDict["first_name"] as! String
            recipient.lastName = userDict["last_name"] as! String
            recipient.email = userDict["email"] as! String
            recipient.phoneNumber = userDict["phone"] as! String
            recipient.gravatarHash = userDict["gravatar_hash"] as! String
            recipient.isMonitor = (Int(truncating: userDict["is_monitor"] as? NSNumber ?? 0)) == 1 ? true : false
            var orgDict = userDict["org"] as? [AnyHashable : Any]
            if orgDict != nil {
                recipient.orgID = orgDict?["id"] as! String
                recipient.orgSlug = orgDict?["slug"] as! String
            } else {
                Logger.debug("Missing orgDictionary for Recipient: \(String(describing: recipient.uniqueId))")
            }
            let tagDict = userDict["tag"] as? [AnyHashable : Any]
            if tagDict != nil {
                recipient.flTag = FLTag.getOrCreateTag(with: tagDict!, transaction: transaction)
                recipient.flTag?.recipientIds = NSCountedSet.init(array: [recipient.uniqueId!])
                if recipient.flTag?.tagDescription?.count == 0 {
                    recipient.flTag?.tagDescription = recipient.fullName()
                }
                if recipient.flTag?.orgSlug.count == 0 {
                    recipient.flTag?.orgSlug = recipient.orgSlug
                }
//                Environment.shared.contactsManager.saveTag(recipient?.flTag, withTransaction: transaction)
                recipient.save(with: transaction)

            } else {
                Logger.debug("Missing tagDictionary for Recipient: \(String(describing: recipient.uniqueId))")
            }
//            Environment.shared.contactsManager.save(recipient, withTransaction: transaction)
            recipient.save(with: transaction)
            return recipient
        } else {
            Logger.debug("\(self.logTag()): \(#function) received invalid dictionary: \(userDict)")
            return nil
        }
    }
    
    class func getOrBuildUnsavedRecipient(forRecipientId recipientId: String, transaction: YapDatabaseReadTransaction?) -> RelayRecipient {
        assert((transaction != nil))
        assert((recipientId.count) > 0)
        
        if let recipient  = self.registeredRecipient(forRecipientId: recipientId, transaction: transaction) {
            return recipient
        } else {
            return RelayRecipient.recipient(uid: recipientId)
        }
    }
    
    class func isRegisteredRecipient(_ recipientId: String, transaction: YapDatabaseReadTransaction) -> Bool {
        let recipient = RelayRecipient.registeredRecipient(forRecipientId: recipientId, transaction: transaction)
        return (recipient != nil)
    }
    
    class func mark(asRegisteredAndGet recipientId: String, transaction: YapDatabaseReadWriteTransaction) -> RelayRecipient? {

        if let recipient = RelayRecipient.registeredRecipient(forRecipientId: recipientId, transaction: transaction) {
            return recipient
        } else {
            Logger.debug("\(self.logTag()) creating recipient: \(recipientId)")
            let recipient = RelayRecipient.init(uniqueId: recipientId)
            recipient.save(with: transaction)
            return recipient
        }
    }
    
    class func mark(asRegistered recipientId: String, deviceId: UInt32, transaction: YapDatabaseReadWriteTransaction) {
        if let recipient = RelayRecipient.fetch(uniqueId: recipientId, transaction: transaction) {
            Logger.debug("\(self.logTag()) in \(#function) adding \(deviceId) to existing recipient.")
            recipient.addDevices(NSOrderedSet.init(array: [ NSNumber.init(value: deviceId) ]))
        }
    }
    
    class func removeUnregisteredRecipient(_ recipientId: String, transaction: YapDatabaseReadWriteTransaction) {
        if let recipient = RelayRecipient.registeredRecipient(forRecipientId: recipientId, transaction: transaction) {
            Logger.debug("\(self.logTag()) removing recipient: \(recipientId)")
            recipient.remove(with: transaction)
        }
    }
        
    func addDevices(toRegisteredRecipient devices: NSOrderedSet, transaction: YapDatabaseReadWriteTransaction) {
        self.addDevices(devices)
        
        let latest = RelayRecipient.mark(asRegisteredAndGet: self.uniqueId!, transaction: transaction)
        
        guard !(devices.isSubset(of: (latest?.devices)!)) else {
            return
        }
        Logger.debug("\(self.logTag) adding devices: \(devices), to recipient: \(String(describing: latest?.uniqueId))")
        latest?.addDevices(devices)
        latest?.save(with: transaction)
    }
    
    func removeDevices(fromRecipient devices: NSOrderedSet, transaction: YapDatabaseReadWriteTransaction) {
        self.removeDevices(devices)
        
        let latest = RelayRecipient.mark(asRegisteredAndGet: self.uniqueId!, transaction: transaction)
        
        guard devices.intersects((latest?.devices)!) else {
            return
        }
        Logger.debug("\(self.logTag) removing devices: \(devices), from recipient: \(String(describing: latest?.uniqueId))")
        latest?.removeDevices(devices)
        latest?.save(with: transaction)
    }
    
    private class func recipient(uid: String?) -> RelayRecipient {
        assert((TSAccountManager.localUID()?.count)! > 0)
        
        let recipient = super.init(uniqueId: uid) as! RelayRecipient
        
        if (TSAccountManager.localUID() == uid) {
            // Default to no devices.
            //
            // This instance represents our own account and is used for sending
            // sync message to linked devices.  We shouldn't have any linked devices
            // yet when we create the "self" SignalRecipient, and we don't need to
            // send sync messages to the primary - we ARE the primary.
            recipient.devices = NSOrderedSet()
        } else {
            // Default to sending to just primary device.
            //
            // OWSMessageSender will correct this if it is wrong the next time
            // we send a message to this recipient.
            recipient.devices = NSOrderedSet(object: 1)
        }
        return recipient
    }

    
    private func addDevices(_ devices: NSOrderedSet) {
        assert(devices.count > 0)
        if (uniqueId?.isEqual(TSAccountManager.localUID()))! && devices.contains(OWSDeviceManager.shared().currentDeviceId()) {
            Logger.error("\(self.logTag) in \(#function) adding self as recipient device")
            return
        }
        let updatedDevices: NSMutableOrderedSet? = self.devices?.mutableCopy() as? NSMutableOrderedSet
        updatedDevices?.union(devices)
        self.devices = updatedDevices
    }
    
    private func removeDevices(_ devices: NSOrderedSet) {
        assert(devices.count > 0)
        let updatedDevices: NSMutableOrderedSet? = self.devices as? NSMutableOrderedSet
        updatedDevices?.minus(devices)
        self.devices = updatedDevices
    }

    
    class func recipientComparator() -> Comparator {
        return { obj1, obj2 in
            let contact1 = obj1 as? RelayRecipient
            let contact2 = obj2 as? RelayRecipient
            let firstNameOrdering = false
            if firstNameOrdering {
                return (contact1?.firstName.caseInsensitiveCompare(contact2?.firstName ?? ""))!
            } else {
                return (contact1?.lastName.caseInsensitiveCompare(contact2?.lastName ?? ""))!
            }
        }
    }
}
