import Foundation

public protocol UserDefaultsType: AnyObject {
    func object(forKey defaultName: String) -> Any?
    func string(forKey defaultName: String) -> String?
    func array(forKey defaultName: String) -> [Any]?
    func dictionary(forKey defaultName: String) -> [String : Any]?
    func data(forKey defaultName: String) -> Data?
    func stringArray(forKey defaultName: String) -> [String]?
    func integer(forKey defaultName: String) -> Int
    func float(forKey defaultName: String) -> Float
    func double(forKey defaultName: String) -> Double
    func bool(forKey defaultName: String) -> Bool
    func url(forKey defaultName: String) -> URL?

    func set(_ value: Any?, forKey defaultName: String)
    func set(_ value: Int, forKey defaultName: String)
    func set(_ value: Float, forKey defaultName: String)
    func set(_ value: Double, forKey defaultName: String)
    func set(_ value: Bool, forKey defaultName: String)
    func set(_ url: URL?, forKey defaultName: String)
}

extension UserDefaults: UserDefaultsType {}

public enum SNUserDefaults {
    
    public enum Bool: Swift.String {
        case hasSyncedInitialConfiguration = "hasSyncedConfiguration"
        case hasSeenLinkPreviewSuggestion
        case hasSeenCallIPExposureWarning
        case hasSeenCallMissedTips
        case isUsingFullAPNs
        case wasUnlinked
        case isMainAppActive
        case isCallOngoing
    }

    public enum Date: Swift.String {
        case lastConfigurationSync
        case lastDisplayNameUpdate
        case lastProfilePictureUpdate
        case lastProfilePictureUpload
        case lastOpenGroupImageUpdate
        case lastOpen
        case lastGarbageCollection
    }

    public enum Double: Swift.String {
        case lastDeviceTokenUpload = "lastDeviceTokenUploadTime"
    }

    public enum Int: Swift.String {
        case appMode
        case hardfork
        case softfork
    }
    
    public enum String : Swift.String {
        case deviceToken
    }
}

public extension UserDefaults {
    @objc static var sharedLokiProject: UserDefaults? {
        UserDefaults(suiteName: "group.com.loki-project.loki-messenger")
    }
}

public extension UserDefaultsType {
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
