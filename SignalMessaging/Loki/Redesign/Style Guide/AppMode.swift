
@objc(LKAppModeManager)
public final class AppModeManager : NSObject {
    private let delegate: AppModeManagerDelegate

    public var currentAppMode: AppMode {
        return delegate.getCurrentAppMode()
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
}

@objc(LKAppModeManagerDelegate)
public protocol AppModeManagerDelegate {

    func getCurrentAppMode() -> AppMode
    func setCurrentAppMode(to appMode: AppMode)
}

@objc(LKAppMode)
public enum AppMode : Int {
    case light, dark
}

public var isLightMode: Bool {
    return AppModeManager.shared.currentAppMode == .light
}

public var isDarkMode: Bool {
    return AppModeManager.shared.currentAppMode == .dark
}

@objc public final class LKAppModeUtilities : NSObject {

    @objc public static var isLightMode: Bool {
        return AppModeManager.shared.currentAppMode == .light
    }

    @objc public static var isDarkMode: Bool {
        return AppModeManager.shared.currentAppMode == .dark
    }
}
