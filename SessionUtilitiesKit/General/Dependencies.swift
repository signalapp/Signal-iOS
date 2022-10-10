// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB

open class Dependencies {
    public var _generalCache: Atomic<Atomic<GeneralCacheType>?>
    public var generalCache: Atomic<GeneralCacheType> {
        get { Dependencies.getValueSettingIfNull(&_generalCache) { General.cache } }
        set { _generalCache.mutate { $0 = newValue } }
    }
    
    public var _storage: Atomic<Storage?>
    public var storage: Storage {
        get { Dependencies.getValueSettingIfNull(&_storage) { Storage.shared } }
        set { _storage.mutate { $0 = newValue } }
    }
    
    public var _scheduler: Atomic<ValueObservationScheduler?>
    public var scheduler: ValueObservationScheduler {
        get { Dependencies.getValueSettingIfNull(&_scheduler) { Storage.defaultPublisherScheduler } }
        set { _scheduler.mutate { $0 = newValue } }
    }
    
    public var _standardUserDefaults: Atomic<UserDefaultsType?>
    public var standardUserDefaults: UserDefaultsType {
        get { Dependencies.getValueSettingIfNull(&_standardUserDefaults) { UserDefaults.standard } }
        set { _standardUserDefaults.mutate { $0 = newValue } }
    }
    
    public var _date: Atomic<Date?>
    public var date: Date {
        get { Dependencies.getValueSettingIfNull(&_date) { Date() } }
        set { _date.mutate { $0 = newValue } }
    }
    
    // MARK: - Initialization
    
    public init(
        generalCache: Atomic<GeneralCacheType>? = nil,
        storage: Storage? = nil,
        scheduler: ValueObservationScheduler? = nil,
        standardUserDefaults: UserDefaultsType? = nil,
        date: Date? = nil
    ) {
        _generalCache = Atomic(generalCache)
        _storage = Atomic(storage)
        _scheduler = Atomic(scheduler)
        _standardUserDefaults = Atomic(standardUserDefaults)
        _date = Atomic(date)
    }
    
    // MARK: - Convenience
    
    public static func getValueSettingIfNull<T>(_ maybeValue: inout Atomic<T?>, _ valueGenerator: () -> T) -> T {
        guard let value: T = maybeValue.wrappedValue else {
            let value: T = valueGenerator()
            maybeValue.mutate { $0 = value }
            return value
        }
        
        return value
    }
}
