// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionUtilitiesKit

@objc
public class SSKPreferences: NSObject {
    // Never instantiate this class.
    private override init() {}

    private static let collection = "SSKPreferences"

    // MARK: -

    private static let areLinkPreviewsEnabledKey = "areLinkPreviewsEnabled"

    @objc
    public static var areLinkPreviewsEnabled: Bool {
        get {
            return getBool(key: areLinkPreviewsEnabledKey, defaultValue: false)
        }
        set {
            setBool(newValue, key: areLinkPreviewsEnabledKey)
        }
    }

    // MARK: -

    private static let hasSavedThreadKey = "hasSavedThread"

    @objc
    public static var hasSavedThread: Bool {
        get {
            return getBool(key: hasSavedThreadKey)
        }
        set {
            setBool(newValue, key: hasSavedThreadKey)
        }
    }

    @objc
    public class func setHasSavedThread(value: Bool, transaction: YapDatabaseReadWriteTransaction) {
        transaction.setBool(value,
                            forKey: hasSavedThreadKey,
                            inCollection: collection)
    }

    // MARK: -

    private class func getBool(key: String, defaultValue: Bool = false) -> Bool {
        return OWSPrimaryStorage.dbReadConnection().bool(forKey: key, inCollection: collection, defaultValue: defaultValue)
    }

    private class func setBool(_ value: Bool, key: String) {
        OWSPrimaryStorage.dbReadWriteConnection().setBool(value, forKey: key, inCollection: collection)
    }
}

// MARK: - Objective C Support

public extension SSKPreferences {
    @objc(setScreenSecurity:)
    static func objc_setScreenSecurity(_ enabled: Bool) {
        GRDBStorage.shared.write { db in db[.preferencesAppSwitcherPreviewEnabled] = enabled }
    }
    
    @objc(areReadReceiptsEnabled)
    static func objc_areReadReceiptsEnabled() -> Bool {
        return GRDBStorage.shared[.areReadReceiptsEnabled]
    }
    
    @objc(setAreReadReceiptsEnabled:)
    static func objc_setAreReadReceiptsEnabled(_ enabled: Bool) {
        GRDBStorage.shared.write { db in db[.areReadReceiptsEnabled] = enabled }
    }
    
    @objc(setTypingIndicatorsEnabled:)
    static func objc_setTypingIndicatorsEnabled(_ enabled: Bool) {
        GRDBStorage.shared.write { db in db[.typingIndicatorsEnabled] = enabled }
    }
    
    @objc(areTypingIndicatorsEnabled)
    static func objc_areTypingIndicatorsEnabled() -> Bool {
        return (GRDBStorage.shared.read { db in db[.typingIndicatorsEnabled] } == true)
    }
}
