//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

public extension Notification.Name {
    static let themeDidChange = Notification.Name("ThemeDidChangeNotification")
}

@objc
public extension NSNotification {
    static var ThemeDidChange: NSString { Notification.Name.themeDidChange.rawValue as NSString }
}

final public class Theme: NSObject {

    public enum Mode: UInt {
        case system, light, dark
    }

    private static var shared = Theme()

    private override init() {
        super.init()
    }

    public static func performInitialSetup(appReadiness: AppReadiness) {
        appReadiness.runNowOrWhenAppDidBecomeReadySync {
            // IOS-782: +[Theme shared] re-enterant initialization
            // AppReadiness will invoke the block synchronously if the app is already ready.
            // This doesn't work here, because we'll end up reenterantly calling +shared
            // if the app is in dark mode and the first call to +[Theme shared] happens
            // after the app is ready.
            //
            // It looks like that pattern is only hit in the share extension, but we're better off
            // asyncing always to ensure the dependency chain is broken. We're okay waiting, since
            // there's no guarantee that this block in synchronously executed anyway.
            DispatchQueue.main.async {
                Self.shared.notifyIfThemeModeIsNotDefault()
            }
        }
    }

    private static var keyValueStore: KeyValueStore {
        return KeyValueStore(collection: "ThemeCollection")
    }

    private struct KVSKeys {
        static var currentMode = "ThemeKeyCurrentMode"
        static var legacyThemeEnabled = "ThemeKeyThemeEnabled"
    }

    public class func setupSignalAppearance() {
        UINavigationBar.appearance().barTintColor = Theme.navbarBackgroundColor
        UINavigationBar.appearance().tintColor = Theme.primaryIconColor
        UIToolbar.appearance().barTintColor = Theme.navbarBackgroundColor
        UIToolbar.appearance().tintColor = Theme.primaryIconColor

        // We do _not_ specify BarButton.appearance().tintColor because it is sufficient to specify
        // UINavigationBar.appearance().tintColor. Furthermore, specifying the BarButtonItem's
        // appearance makes it more difficult to override the navbar theme, e.g. how we _always_
        // use dark theme in the media send flow and gallery views. If we were specifying
        // barButton.appearance().tintColor we would then have to manually override each
        // BarButtonItem's tint, rather than just the navbars.
        //
        // UIBarButtonItem.appearance.tintColor = Theme.primaryIconColor;

        // Using UIText{View,Field}.appearance().keyboardAppearance crashes due to a bug in UIKit,
        // so we don't do it.

        UITableViewCell.appearance().tintColor = Theme.primaryIconColor
        UIToolbar.appearance().tintColor = .ows_accentBlue

        // If we set NSShadowAttributeName, the NSForegroundColorAttributeName value is ignored.
        UINavigationBar.appearance().titleTextAttributes = [
            NSAttributedString.Key.foregroundColor: Theme.navbarTitleColor
        ]

        let cursorColor = isDarkThemeEnabled ? UIColor.white : UIColor.ows_accentBlue
        UITextView.appearance(whenContainedInInstancesOf: [OWSNavigationController.self]).tintColor = cursorColor
        UITextField.appearance(whenContainedInInstancesOf: [OWSNavigationController.self]).tintColor = cursorColor
    }

    // MARK: - Theme Mode

    public static var isDarkThemeEnabled: Bool { shared.isDarkThemeEnabled }

    public class func getOrFetchCurrentMode() -> Mode {
        return shared.getOrFetchCurrentMode()
    }

    public class func setCurrentMode(_ mode: Mode) {
        shared.setCurrentMode(mode)
    }

    public class func performWithModeAsCurrent(_ mode: Mode, _ operation: () -> Void) {
        shared.performWithModeAsCurrent(mode, operation)
    }

    private func performWithModeAsCurrent(_ mode: Mode, _ operation: () -> Void) {
        let previousMode = cachedCurrentMode
        defer { cachedCurrentMode = previousMode }
        cachedCurrentMode = mode
        operation()
    }

    private var cachedIsDarkThemeEnabled: Bool?
    private var cachedCurrentMode: Mode?

    public static var shareExtensionThemeOverride: UIUserInterfaceStyle = .unspecified {
        didSet {
            guard !CurrentAppContext().isMainApp else {
                return owsFailDebug("Should only be set in share extension")
            }
            shared.themeDidChange()
        }
    }

    private var isDarkThemeEnabled: Bool {
#if TESTABLE_BUILD
        if let isDarkThemeEnabledForTests {
            return isDarkThemeEnabledForTests
        }
#endif

        // Don't cache this value until it reflects the data store.
        guard AppReadinessObjcBridge.isAppReady else {
            return isSystemDarkThemeEnabled()
        }

        // Always respect the system theme in extensions.
        guard CurrentAppContext().isMainApp else {
            return switch Self.shareExtensionThemeOverride {
            case .dark:
                true
            case .light:
                false
            case .unspecified:
                isSystemDarkThemeEnabled()
            @unknown default:
                isSystemDarkThemeEnabled()
            }
        }

        if let cachedIsDarkThemeEnabled {
            return cachedIsDarkThemeEnabled
        }

        let isDarkThemeEnabled: Bool = {
            switch getOrFetchCurrentMode() {
            case .system: return isSystemDarkThemeEnabled()
            case .dark: return true
            case .light: return false
            }
        }()
        cachedIsDarkThemeEnabled = isDarkThemeEnabled

        return isDarkThemeEnabled
    }

    private func isSystemDarkThemeEnabled() -> Bool {
        return UITraitCollection.current.userInterfaceStyle == .dark
    }

    private func getOrFetchCurrentMode() -> Mode {
        if let cachedCurrentMode {
            return cachedCurrentMode
        }

        guard AppReadinessObjcBridge.isAppReady else {
            return defaultMode
        }

        var currentMode: Mode = .system
        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            let hasDefinedMode = Theme.keyValueStore.hasValue(KVSKeys.currentMode, transaction: transaction.asV2Read)
            if hasDefinedMode {
                let rawMode = Theme.keyValueStore.getUInt(
                    KVSKeys.currentMode,
                    defaultValue: Theme.Mode.system.rawValue,
                    transaction: transaction.asV2Read
                )
                if let definedMode = Mode(rawValue: rawMode) {
                    currentMode = definedMode
                }
            } else {
                // If the theme has not yet been defined, check if the user ever manually changed
                // themes in a legacy app version. If so, preserve their selection. Otherwise,
                // default to matching the system theme.
                if Theme.keyValueStore.hasValue(KVSKeys.legacyThemeEnabled, transaction: transaction.asV2Read) {
                    let isLegacyModeDark = Theme.keyValueStore.getBool(
                        KVSKeys.legacyThemeEnabled,
                        defaultValue: false,
                        transaction: transaction.asV2Read
                    )
                    currentMode = isLegacyModeDark ? .dark : .light
                }
            }
        }

        cachedCurrentMode = currentMode

        return currentMode
    }

    private func setCurrentMode(_ mode: Mode) {
        AssertIsOnMainThread()

        let previousMode = cachedCurrentMode

        switch mode {
        case .light:
            cachedIsDarkThemeEnabled = false
        case .dark:
            cachedIsDarkThemeEnabled = true
        case .system:
            cachedIsDarkThemeEnabled = isSystemDarkThemeEnabled()
        }

        cachedCurrentMode = mode

        // It's safe to do an async write because all accesses check self.cachedCurrentThemeNumber first.
        SSKEnvironment.shared.databaseStorageRef.asyncWrite { transaction in
            Theme.keyValueStore.setUInt(mode.rawValue, key: KVSKeys.currentMode, transaction: transaction.asV2Write)
        }

        if previousMode != mode {
            themeDidChange()
        }
    }

    private var defaultMode: Mode {
        return .system
    }

    private func notifyIfThemeModeIsNotDefault() {
        if isDarkThemeEnabled || defaultMode != getOrFetchCurrentMode() {
            themeDidChange()
        }
    }

    // MARK: -

    class func systemThemeChanged() {
        shared.systemThemeChanged()
    }

    private func systemThemeChanged() {
        // Do nothing, since we haven't setup the theme yet.
        guard cachedIsDarkThemeEnabled != nil else { return }

        // Theme can only be changed externally when in system mode.
        guard getOrFetchCurrentMode() == .system else { return }

        // We may get multiple updates for the same change.
        let isSystemDarkThemeEnabled = isSystemDarkThemeEnabled()
        guard cachedIsDarkThemeEnabled != isSystemDarkThemeEnabled else { return }

        cachedIsDarkThemeEnabled = isSystemDarkThemeEnabled
        themeDidChange()
    }

    private func themeDidChange() {
        Theme.setupSignalAppearance()
        NotificationCenter.default.post(name: .themeDidChange, object: self)
    }

    // MARK: - UI Colors

    private static var currentThemeTraitCollection: UITraitCollection {
        isDarkThemeEnabled ? darkTraitCollection : lightTraitCollection
    }

    private static var lightTraitCollection: UITraitCollection {
        UITraitCollection(userInterfaceStyle: .light)
    }

    private static var darkTraitCollection: UITraitCollection {
        UITraitCollection(userInterfaceStyle: .dark)
    }

    private static var elevatedLightTraitCollection: UITraitCollection {
        UITraitCollection(traitsFrom: [
            lightTraitCollection,
            UITraitCollection(userInterfaceLevel: .elevated),
        ])
    }

    private static var elevatedDarkTraitCollection: UITraitCollection {
        UITraitCollection(traitsFrom: [
            darkTraitCollection,
            UITraitCollection(userInterfaceLevel: .elevated),
        ])
    }

    @objc
    public class var backgroundColor: UIColor {
        isDarkThemeEnabled
        ? darkThemeBackgroundColor
        : UIColor.Signal.background.resolvedColor(with: lightTraitCollection)
    }

    public class var secondaryBackgroundColor: UIColor {
        isDarkThemeEnabled
        ? darkThemeSecondaryBackgroundColor
        : UIColor.Signal.secondaryBackground.resolvedColor(with: lightTraitCollection)
    }

    public class var darkThemeSecondaryBackgroundColor: UIColor {
        UIColor.Signal.secondaryBackground.resolvedColor(with: darkTraitCollection)
    }

    public class var washColor: UIColor {
        isDarkThemeEnabled ? darkThemeWashColor : .ows_gray05
    }

    public class var primaryTextColor: UIColor {
        isDarkThemeEnabled ? darkThemePrimaryColor : lightThemePrimaryColor
    }

    public class var primaryIconColor: UIColor {
        isDarkThemeEnabled ? darkThemeNavbarIconColor : .ows_gray75
    }

    public class var secondaryTextAndIconColor: UIColor {
        isDarkThemeEnabled ? darkThemeSecondaryTextAndIconColor : lightThemeSecondaryTextAndIconColor
    }

    public class var ternaryTextColor: UIColor {
        UIColor.Signal.tertiaryLabel.resolvedColor(with: currentThemeTraitCollection)
    }

    public class var snippetColor: UIColor {
        isDarkThemeEnabled ? darkThemeSnippetColor : lightThemeSnippetColor
    }

    public class var hairlineColor: UIColor {
        UIColor.Signal.opaqueSeparator.resolvedColor(with: currentThemeTraitCollection)
    }

    public class var outlineColor: UIColor {
        hairlineColor
    }

    public class var backdropColor: UIColor { .ows_blackAlpha40 }

    public class var navbarBackgroundColor: UIColor {
        backgroundColor
    }

    public class var navbarTitleColor: UIColor { primaryTextColor }

    public class var toolbarBackgroundColor: UIColor { navbarBackgroundColor }

    // For accessibility:
    //
    // * Flat areas (e.g. button backgrounds) should use UIColor.ows_accentBlue.
    // * Fine detail (e.g., text, non-filled icons) should use Theme.accentBlueColor.
    //   It is brighter in dark mode, improving legibility.
    public class var accentBlueColor: UIColor {
        UIColor.Signal.accent.resolvedColor(with: currentThemeTraitCollection)
    }

    public class var conversationButtonBackgroundColor: UIColor {
        isDarkThemeEnabled ? .ows_gray80 : .ows_gray02
    }

    public class var conversationButtonTextColor: UIColor {
        isDarkThemeEnabled ? .ows_gray05 : .ows_accentBlue
    }

    @objc
    public class var launchScreenBackgroundColor: UIColor {
        backgroundColor
    }

    // MARK: - Table View

    public class var cellSelectedColor: UIColor {
        isDarkThemeEnabled ? UIColor(white: 0.2, alpha: 1) : UIColor(white: 0.92, alpha: 1)
    }

    public class var cellSeparatorColor: UIColor { hairlineColor }

    public class var tableCell2BackgroundColor: UIColor {
        isDarkThemeEnabled
        ? darkThemeTableCell2BackgroundColor
        : UIColor.Signal.secondaryGroupedBackground.resolvedColor(with: lightTraitCollection)
    }

    public class var tableCell2PresentedBackgroundColor: UIColor {
        isDarkThemeEnabled
        ? darkThemeTableCell2PresentedBackgroundColor
        : UIColor.Signal.secondaryGroupedBackground.resolvedColor(with: elevatedLightTraitCollection)
    }

    public class var tableCell2SelectedBackgroundColor: UIColor {
        isDarkThemeEnabled ? darkThemeTableCell2SelectedBackgroundColor : .ows_gray15
    }

    public class var tableCell2SelectedBackgroundColor2: UIColor {
        isDarkThemeEnabled ? darkThemeTableCell2SelectedBackgroundColor2 : .ows_gray15
    }

    public class var tableCell2MultiSelectedBackgroundColor: UIColor {
        isDarkThemeEnabled ? darkThemeTableCell2MultiSelectedBackgroundColor : .ows_gray05
    }

    public class var tableCell2PresentedSelectedBackgroundColor: UIColor {
        isDarkThemeEnabled ? darkThemeTableCell2PresentedSelectedBackgroundColor : .ows_gray15
    }

    public class var tableView2BackgroundColor: UIColor {
        isDarkThemeEnabled
        ? darkThemeTableView2BackgroundColor
        : UIColor.Signal.groupedBackground.resolvedColor(with: lightTraitCollection)
    }

    public class var tableView2PresentedBackgroundColor: UIColor {
        isDarkThemeEnabled
        ? darkThemeTableView2PresentedBackgroundColor
        : UIColor.Signal.groupedBackground.resolvedColor(with: elevatedLightTraitCollection)
    }

    public class var tableView2SeparatorColor: UIColor {
        isDarkThemeEnabled ? darkThemeTableView2SeparatorColor : .ows_gray20
    }

    public class var tableView2PresentedSeparatorColor: UIColor {
        isDarkThemeEnabled ? darkThemeTableView2PresentedSeparatorColor : .ows_gray20
    }

    // MARK: - Light Theme Colors

    public class var lightThemePrimaryColor: UIColor {
        UIColor.Signal.label.resolvedColor(with: lightTraitCollection)
    }

    public class var lightThemeSecondaryTextAndIconColor: UIColor {
        UIColor.Signal.secondaryLabel.resolvedColor(with: lightTraitCollection)
    }

    public class var lightThemeSnippetColor: UIColor { .ows_gray45 }

    // MARK: - Dark Theme Colors

    public class var darkThemeBackgroundColor: UIColor {
        UIColor.Signal.background.resolvedColor(with: darkTraitCollection)
    }

    public class var darkThemePrimaryColor: UIColor {
        UIColor.Signal.label.resolvedColor(with: darkTraitCollection)
    }

    public class var darkThemeSecondaryTextAndIconColor: UIColor {
        UIColor.Signal.secondaryLabel.resolvedColor(with: darkTraitCollection)
     }

    public class var darkThemeSnippetColor: UIColor { .ows_gray25 }

    public class var darkThemeWashColor: UIColor { .ows_gray75 }

    public class var darkThemeNavbarBackgroundColor: UIColor {
        darkThemeBackgroundColor
    }

    public class var darkThemeNavbarIconColor: UIColor { .ows_gray15 }

    public class var darkThemeTableCell2BackgroundColor: UIColor {
        UIColor.Signal.secondaryGroupedBackground.resolvedColor(with: darkTraitCollection)
    }

    public class var darkThemeTableCell2PresentedBackgroundColor: UIColor {
        UIColor.Signal.secondaryGroupedBackground.resolvedColor(with: elevatedDarkTraitCollection)
    }

    public class var darkThemeTableCell2SelectedBackgroundColor: UIColor { .ows_gray80 }

    public class var darkThemeTableCell2SelectedBackgroundColor2: UIColor { .ows_gray65 }

    public class var darkThemeTableCell2MultiSelectedBackgroundColor: UIColor { .ows_gray75 }

    public class var darkThemeTableCell2PresentedSelectedBackgroundColor: UIColor { .ows_gray75 }

    public class var darkThemeTableView2BackgroundColor: UIColor {
        UIColor.Signal.groupedBackground.resolvedColor(with: darkTraitCollection)
    }

    public class var darkThemeTableView2PresentedBackgroundColor: UIColor {
        UIColor.Signal.groupedBackground.resolvedColor(with: elevatedDarkTraitCollection)
    }

    public class var darkThemeTableView2SeparatorColor: UIColor { .ows_gray75 }

    public class var darkThemeTableView2PresentedSeparatorColor: UIColor { .ows_gray65 }

    // MARK: - Blur Effect

    public class var barBlurEffect: UIBlurEffect {
        isDarkThemeEnabled ? darkThemeBarBlurEffect : UIBlurEffect(style: .light)
    }

    public class var darkThemeBarBlurEffect: UIBlurEffect { UIBlurEffect(style: .dark) }

    // MARK: - Keyboard

    public class var keyboardAppearance: UIKeyboardAppearance {
        isDarkThemeEnabled ? darkThemeKeyboardAppearance : .default
    }

    public class var darkThemeKeyboardAppearance: UIKeyboardAppearance { .dark }

    public class var keyboardBackgroundColor: UIColor {
        isDarkThemeEnabled ? .ows_gray90 : .ows_gray02
    }

    // MARK: - Search Bar

    public class var barStyle: UIBarStyle {
        isDarkThemeEnabled ? .black : .default
    }

    public class var searchFieldBackgroundColor: UIColor { washColor }

    public class var searchFieldElevatedBackgroundColor: UIColor {
        isDarkThemeEnabled ? .ows_gray75 : .ows_gray12
    }

#if TESTABLE_BUILD
    private var isDarkThemeEnabledForTests: Bool?

    public class func setIsDarkThemeEnabledForTests(_ enabled: Bool) {
        shared.isDarkThemeEnabledForTests = enabled
    }
#endif
}
