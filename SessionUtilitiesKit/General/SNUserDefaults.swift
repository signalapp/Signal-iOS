import Foundation

public enum SNUserDefaults {
    
    public enum Bool : Swift.String {
        case hasSyncedInitialConfiguration = "hasSyncedConfiguration"
        case hasViewedSeed
        case hasSeenLinkPreviewSuggestion
        case hasSeenCallIPExposureWarning
        case hasSeenCallMissedTips
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
        case hardfork
        case softfork
    }
    
    public enum String : Swift.String {
        case deviceToken
    }
    
    public enum Array : Swift.String {
        case recentlyUsedEmojis
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
    
    subscript(array: SNUserDefaults.Array) -> [String] {
        get { return self.stringArray(forKey: array.rawValue) ?? []}
        set { set(newValue, forKey: array.rawValue) }
    }
    
    func getRecentlyUsedEmojis() -> [String] {
        let result = self[.recentlyUsedEmojis]
        if result.isEmpty {
            return ["🙈", "🙉", "🙊", "😈", "🥸", "🐀"]
        }
        return result
    }
    
    func addNewRecentlyUsedEmoji(_ emoji: String) {
        var recentlyUsedEmojis = getRecentlyUsedEmojis()
        if let index = recentlyUsedEmojis.firstIndex(of: emoji) {
            recentlyUsedEmojis.remove(at: index)
        }
        if recentlyUsedEmojis.count >= 6 {
            recentlyUsedEmojis.remove(at: 5)
        }
        recentlyUsedEmojis.insert(emoji, at: 0)
        self[.recentlyUsedEmojis] = recentlyUsedEmojis
    }
}
