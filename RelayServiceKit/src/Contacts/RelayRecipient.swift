//
//  RelayRecipient.swift
//  RelayServiceKit
//
//  Created by Mark Descalzo on 8/14/18.
//

import Foundation
import YapDatabase

@objc class RelayRecipient: TSYapDatabaseObject {
    
    private(set) var devices: NSOrderedSet?

    // Forsta additions - departure from Contact usage
    var firstName = ""
    var lastName = ""
    var phoneNumber = ""
    var email = ""
    var notes = ""
    var flTag: FLTag?
    var avatar: UIImage?
    var orgSlug = ""
    var orgID = ""
    var gravatarHash = ""
    var gravatarImage: UIImage?
    var hiddenDate: Date?
    var isMonitor = false
    var isActive = false

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
    
    class func registeredRecipient(forRecipientId recipientId: String?, transaction: YapDatabaseReadTransaction?) -> RelayRecipient? {
    }
    
    class func getOrBuildUnsavedRecipient(forRecipientId recipientId: String?, transaction: YapDatabaseReadTransaction?) -> RelayRecipient {
    }
    
    class func isRegisteredRecipient(_ recipientId: String?, transaction: YapDatabaseReadTransaction?) -> Bool {
    }
    
    class func mark(asRegisteredAndGet recipientId: String?, transaction: YapDatabaseReadWriteTransaction?) -> RelayRecipient? {
    }
    
    class func mark(asRegistered recipientId: String?, deviceId: UInt32, transaction: YapDatabaseReadWriteTransaction?) {
    }
    
    class func removeUnregisteredRecipient(_ recipientId: String?, transaction: YapDatabaseReadWriteTransaction?) {
    }
        
    func addDevices(toRegisteredRecipient devices: Set<AnyHashable>?, transaction: YapDatabaseReadWriteTransaction?) {
    }
    
    func removeDevices(fromRecipient devices: Set<AnyHashable>?, transaction: YapDatabaseReadWriteTransaction?) {
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
