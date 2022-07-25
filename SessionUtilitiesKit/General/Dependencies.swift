// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

open class Dependencies {
    public var _generalCache: Atomic<GeneralCacheType>?
    public var generalCache: Atomic<GeneralCacheType> {
        get { Dependencies.getValueSettingIfNull(&_generalCache) { General.cache } }
        set { _generalCache = newValue }
    }
    
    public var _storage: Storage?
    public var storage: Storage {
        get { Dependencies.getValueSettingIfNull(&_storage) { Storage.shared } }
        set { _storage = newValue }
    }
    
    public var _standardUserDefaults: UserDefaultsType?
    public var standardUserDefaults: UserDefaultsType {
        get { Dependencies.getValueSettingIfNull(&_standardUserDefaults) { UserDefaults.standard } }
        set { _standardUserDefaults = newValue }
    }
    
    public var _date: Date?
    public var date: Date {
        get { Dependencies.getValueSettingIfNull(&_date) { Date() } }
        set { _date = newValue }
    }
    
    // MARK: - Initialization
    
    public init(
        generalCache: Atomic<GeneralCacheType>? = nil,
        storage: Storage? = nil,
        standardUserDefaults: UserDefaultsType? = nil,
        date: Date? = nil
    ) {
        _generalCache = generalCache
        _storage = storage
        _standardUserDefaults = standardUserDefaults
        _date = date
    }
    
    // MARK: - Convenience

    public static func getValueSettingIfNull<T>(_ maybeValue: inout T?, _ valueGenerator: () -> T) -> T {
        guard let value: T = maybeValue else {
            let value: T = valueGenerator()
            maybeValue = value
            return value
        }
        
        return value
    }
}
