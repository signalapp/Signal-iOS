import UIKit

@objc(LKAppModeManager)
public final class AppModeManager : NSObject {
    private let delegate: AppModeManagerDelegate

    public var currentAppMode: AppMode {
        return AppModeManager.getAppModeOrSystemDefault()
    }

    public static var shared: AppModeManager!

    @objc(configureWithDelegate:)
    public static func configure(delegate: AppModeManagerDelegate) {
        shared = AppModeManager(delegate: delegate)
    }

    private init(delegate: AppModeManagerDelegate) {
        self.delegate = delegate
        super.init()
    }

    private override init() { preconditionFailure("Use init(delegate:) instead.") }

    public func setCurrentAppMode(to appMode: AppMode) {
        delegate.setCurrentAppMode(to: appMode)
    }
    
    public func setAppModeToSystemDefault() {
        delegate.setAppModeToSystemDefault()
    }
    
    @objc public static func getAppModeOrSystemDefault() -> AppMode {
        let userDefaults = UserDefaults.standard
        
        guard userDefaults.dictionaryRepresentation().keys.contains("appMode") else {
            return (UITraitCollection.current.userInterfaceStyle == .dark ? .dark : .light)
        }
        
        let mode = userDefaults.integer(forKey: "appMode")
        return AppMode(rawValue: mode) ?? .light
    }
}

@objc(LKAppModeManagerDelegate)
public protocol AppModeManagerDelegate {

    @objc(setCurrentAppMode:)
    func setCurrentAppMode(to appMode: AppMode)
    func setAppModeToSystemDefault()
}

@objc(LKAppMode)
public enum AppMode: Int {
    case light, dark
}

public var isSystemDefault: Bool {
    return !UserDefaults.standard.dictionaryRepresentation().keys.contains("appMode")
}

public var isLightMode: Bool {
    return AppModeManager.shared.currentAppMode == .light
}

public var isDarkMode: Bool {
    return AppModeManager.shared.currentAppMode == .dark
}

@objc public final class LKAppModeUtilities : NSObject {
    
    @objc public static var isSystemDefault: Bool {
        return !UserDefaults.standard.dictionaryRepresentation().keys.contains("appMode")
    }

    @objc public static var isLightMode: Bool {
        return AppModeManager.shared.currentAppMode == .light
    }

    @objc public static var isDarkMode: Bool {
        return AppModeManager.shared.currentAppMode == .dark
    }
}
