import Foundation

public enum LKUserDefaults {
    
    public enum Bool : Swift.String {
        case hasLaunchedOnce
        case hasSeenGIFMetadataWarning
        case hasSeenMultiDeviceRemovalSheet
        case hasSeenOpenGroupSuggestionSheet
        case hasViewedSeed
        /// Whether the device was unlinked as a slave device (used to notify the user on the landing screen).
        case wasUnlinked
        case isUsingFullAPNs
    }

    public enum Date : Swift.String {
        case lastProfilePictureUpload
    }

    public enum Double : Swift.String {
        case lastDeviceTokenUpload = "lastDeviceTokenUploadTime"
    }

    public enum Int: Swift.String {
        case appMode
    }
    
    public enum String {
        case slaveDeviceName(Swift.String)
        case deviceToken
        /// `nil` if this is a master device or if the user hasn't linked a device.
        case masterHexEncodedPublicKey
        
        public var key: Swift.String {
            switch self {
            case .slaveDeviceName(let hexEncodedPublicKey): return "\(hexEncodedPublicKey)_display_name"
            case .deviceToken: return "deviceToken"
            case .masterHexEncodedPublicKey: return "masterDeviceHexEncodedPublicKey"
            }
        }
    }
}

public extension UserDefaults {
    
    public subscript(bool: LKUserDefaults.Bool) -> Bool {
        get { return self.bool(forKey: bool.rawValue) }
        set { set(newValue, forKey: bool.rawValue) }
    }

    public subscript(date: LKUserDefaults.Date) -> Date? {
        get { return self.object(forKey: date.rawValue) as? Date }
        set { set(newValue, forKey: date.rawValue) }
    }
    
    public subscript(double: LKUserDefaults.Double) -> Double {
        get { return self.double(forKey: double.rawValue) }
        set { set(newValue, forKey: double.rawValue) }
    }

    public subscript(int: LKUserDefaults.Int) -> Int {
        get { return self.integer(forKey: int.rawValue) }
        set { set(newValue, forKey: int.rawValue) }
    }
    
    public subscript(string: LKUserDefaults.String) -> String? {
        get { return self.string(forKey: string.key) }
        set { set(newValue, forKey: string.key) }
    }
    
    public var isMasterDevice: Bool {
        return (self[.masterHexEncodedPublicKey] == nil)
    }
}
