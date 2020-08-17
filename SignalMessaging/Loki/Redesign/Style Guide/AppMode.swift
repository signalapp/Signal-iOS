
public enum AppMode {
    case light, dark
    
    public static var current: AppMode = .dark
//    public static var current: AppMode {
//        return UserDefaults.standard[.isUsingDarkMode] ? .dark : .light
//    }
}

public var isLightMode: Bool {
    return AppMode.current == .light
}

public var isDarkMode: Bool {
    return AppMode.current == .dark
}

@objc public final class LKAppModeUtilities : NSObject {

    @objc public static var isLightMode: Bool {
        return AppMode.current == .light
    }

    @objc public static var isDarkMode: Bool {
        return AppMode.current == .dark
    }
}
