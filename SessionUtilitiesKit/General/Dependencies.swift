// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

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
        standardUserDefaults: UserDefaultsType? = nil,
        date: Date? = nil
    ) {
        _generalCache = Atomic(generalCache)
        _storage = Atomic(storage)
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
    
//    0   libswiftCore.dylib                0x00000001999fd40c _swift_release_dealloc + 32 (HeapObject.cpp:703)
//    1   SessionMessagingKit               0x0000000106aa958c 0x106860000 + 2397580
//    2   libswiftCore.dylib                0x00000001999fd424 _swift_release_dealloc + 56 (HeapObject.cpp:703)
//    3   SessionUtilitiesKit               0x0000000106cbd980 static Dependencies.getValueSettingIfNull<A>(_:_:) + 264 (Dependencies.swift:49)
//    4   SessionMessagingKit               0x0000000106aa90f4 closure #1 in SMKDependencies.sign.getter + 112 (SMKDependencies.swift:17)
//    5   SessionUtilitiesKit               0x0000000106cbd974 static Dependencies.getValueSettingIfNull<A>(_:_:) + 252 (Dependencies.swift:48)
//    6   SessionMessagingKit               0x000000010697aef8 specialized static OpenGroupAPI.sign(_:messageBytes:for:fallbackSigningType:using:) + 1158904 (OpenGroupAPI.swift:1190)
}
