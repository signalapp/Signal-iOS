import Foundation

public enum SNUserDefaults {
    
    public enum Bool : Swift.String {
        case hasSyncedInitialConfiguration = "hasSyncedConfiguration"
        case hasViewedSeed
        case hasSeenLinkPreviewSuggestion
        case isUsingFullAPNs
        case hasHiddenMessageRequests
    }

    public enum Date : Swift.String {
        case lastConfigurationSync
        case lastDisplayNameUpdate
        case lastProfilePictureUpdate
        case lastOpenGroupImageUpdate
        case lastOpen
    }

    public enum Double : Swift.String {
        case lastDeviceTokenUpload = "lastDeviceTokenUploadTime"
    }

    public enum Int : Swift.String {
        case appMode
    }
    
    public enum String : Swift.String {
        case deviceToken
    }
}

public extension UserDefaults {
    
    subscript(bool: SNUserDefaults.Bool) -> Bool {
        get { return self.bool(forKey: bool.rawValue) }
        set { set(newValue, forKey: bool.rawValue) }
    }

    subscript(date: SNUserDefaults.Date) -> Date? {
        get { return self.object(forKey: date.rawValue) as? Date }
        set { set(newValue, forKey: date.rawValue) }
    }
    
    subscript(double: SNUserDefaults.Double) -> Double {
        get { return self.double(forKey: double.rawValue) }
        set { set(newValue, forKey: double.rawValue) }
    }

    subscript(int: SNUserDefaults.Int) -> Int {
        get { return self.integer(forKey: int.rawValue) }
        set { set(newValue, forKey: int.rawValue) }
    }
    
    subscript(string: SNUserDefaults.String) -> String? {
        get { return self.string(forKey: string.rawValue) }
        set { set(newValue, forKey: string.rawValue) }
    }
}
