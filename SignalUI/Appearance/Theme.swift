//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public extension Notification.Name {
    static let themeDidChange = Notification.Name("ThemeDidChangeNotification")
}

@objc
public extension NSNotification {
    static var ThemeDidChange: NSString { Notification.Name.themeDidChange.rawValue as NSString }
}

@objc
final public class Theme: NSObject {

    public enum Mode: UInt {
        case system, light, dark
    }

    private static var shared = Theme()

    private override init() {
        super.init()

        AppReadiness.runNowOrWhenAppDidBecomeReadySync {
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
                self.notifyIfThemeModeIsNotDefault()
            }
        }
    }

    private static var keyValueStore: SDSKeyValueStore {
        return SDSKeyValueStore(collection: "ThemeCollection")
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

    @objc
    public static var isDarkThemeEnabled: Bool { shared.isDarkThemeEnabled }

    public class func getOrFetchCurrentMode() -> Mode {
        return shared.getOrFetchCurrentMode()
    }

    public class func setCurrentMode(_ mode: Mode) {
        shared.setCurrentMode(mode)
    }

    private var cachedIsDarkThemeEnabled: Bool?
    private var cachedCurrentMode: Mode?

    private var isDarkThemeEnabled: Bool {
#if TESTABLE_BUILD
        if let isDarkThemeEnabledForTests {
            return isDarkThemeEnabledForTests
        }
#endif

        // Don't cache this value until it reflects the data store.
        guard AppReadiness.isAppReady else {
            return isSystemDarkThemeEnabled()
        }

        // Always respect the system theme in extensions.
        guard CurrentAppContext().isMainApp else {
            return isSystemDarkThemeEnabled()
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
        guard #available(iOS 13, *) else {
            return false
        }
        return UITraitCollection.current.userInterfaceStyle == .dark
    }

    private func getOrFetchCurrentMode() -> Mode {
        if let cachedCurrentMode {
            return cachedCurrentMode
        }

        guard AppReadiness.isAppReady else {
            return defaultMode
        }

        var currentMode: Mode = .system
        databaseStorage.read { transaction in
            let hasDefinedMode = Theme.keyValueStore.hasValue(forKey: KVSKeys.currentMode, transaction: transaction)
            if hasDefinedMode {
                let rawMode = Theme.keyValueStore.getUInt(
                    KVSKeys.currentMode,
                    defaultValue: Theme.Mode.system.rawValue,
                    transaction: transaction
                )
                if let definedMode = Mode(rawValue: rawMode) {
                    currentMode = definedMode
                }
            } else {
                // If the theme has not yet been defined, check if the user ever manually changed
                // themes in a legacy app version. If so, preserve their selection. Otherwise,
                // default to matching the system theme.
                if Theme.keyValueStore.hasValue(forKey: KVSKeys.legacyThemeEnabled, transaction: transaction) {
                    let isLegacyModeDark = Theme.keyValueStore.getBool(
                        KVSKeys.legacyThemeEnabled,
                        defaultValue: false,
                        transaction: transaction
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

        let wasDarkThemeEnabled = cachedIsDarkThemeEnabled

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
        databaseStorage.asyncWrite { transaction in
            Theme.keyValueStore.setUInt(mode.rawValue, key: KVSKeys.currentMode, transaction: transaction)
        }

        if wasDarkThemeEnabled != cachedIsDarkThemeEnabled {
            themeDidChange()
        }
    }

    private var defaultMode: Mode {
        guard #available(iOS 13, *) else {
            return .light
        }
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

        UIView.performWithoutAnimation {
            NotificationCenter.default.post(name: Notification.Name.themeDidChange, object: nil)
        }
    }

    // MARK: - UI Colors

    @objc
    public class var backgroundColor: UIColor {
        isDarkThemeEnabled ? darkThemeBackgroundColor : .white
    }

    public class var secondaryBackgroundColor: UIColor {
        isDarkThemeEnabled ? .ows_gray80 : .ows_gray02
    }

    @objc
    public class var washColor: UIColor {
        isDarkThemeEnabled ? darkThemeWashColor : .ows_gray05
    }

    @objc
    public class var primaryTextColor: UIColor {
        isDarkThemeEnabled ? darkThemePrimaryColor : lightThemePrimaryColor
    }

    public class var primaryIconColor: UIColor {
        isDarkThemeEnabled ? darkThemeNavbarIconColor : .ows_gray75
    }

    @objc
    public class var secondaryTextAndIconColor: UIColor {
        isDarkThemeEnabled ? darkThemeSecondaryTextAndIconColor : .ows_gray60
    }

    public class var ternaryTextColor: UIColor { .ows_gray45 }

    public class var placeholderColor: UIColor { .ows_gray45 }

    public class var hairlineColor: UIColor {
        isDarkThemeEnabled ? .ows_gray75 : .ows_gray15
    }

    public class var outlineColor: UIColor {
        isDarkThemeEnabled ? .ows_gray75 : .ows_gray15
    }

    public class var backdropColor: UIColor { .ows_blackAlpha40 }

    public class var navbarBackgroundColor: UIColor {
        isDarkThemeEnabled ? darkThemeNavbarBackgroundColor : .white
    }

    public class var navbarTitleColor: UIColor { primaryTextColor }

    public class var toolbarBackgroundColor: UIColor { navbarBackgroundColor }

    // For accessibility:
    //
    // * Flat areas (e.g. button backgrounds) should use UIColor.ows_accentBlue.
    // * Fine detail (e.g., text, non-filled icons) should use Theme.accentBlueColor.
    //   It is brighter in dark mode, improving legibility.
    @objc
    public class var accentBlueColor: UIColor {
        isDarkThemeEnabled ? .ows_accentBlueDark : .ows_accentBlue
    }

    public class var conversationButtonBackgroundColor: UIColor {
        isDarkThemeEnabled ? .ows_gray80 : .ows_gray02
    }

    public class var conversationButtonTextColor: UIColor {
        isDarkThemeEnabled ? .ows_gray05 : .ows_accentBlue
    }

    @objc
    public class var launchScreenBackgroundColor: UIColor {
        // We only adapt for dark theme on iOS 13+, because only iOS 13 supports
        // handling dark / light appearance in the launch screen storyboard.
        guard #available(iOS 13, *) else { return .ows_signalBlue }
        return isDarkThemeEnabled ? .ows_signalBlueDark : .ows_signalBlue
    }

    // MARK: - Table View

    public class var cellSelectedColor: UIColor {
        isDarkThemeEnabled ? UIColor(white: 0.2, alpha: 1) : UIColor(white: 0.92, alpha: 1)
    }

    @objc
    public class var cellSeparatorColor: UIColor { hairlineColor }

    public class var tableCell2BackgroundColor: UIColor {
        isDarkThemeEnabled ? darkThemeTableCell2BackgroundColor : .white
    }

    public class var tableCell2PresentedBackgroundColor: UIColor {
        isDarkThemeEnabled ? darkThemeTableCell2PresentedBackgroundColor : .white
    }

    @objc
    public class var tableCell2SelectedBackgroundColor: UIColor {
        isDarkThemeEnabled ? darkThemeTableCell2SelectedBackgroundColor : .ows_gray15
    }

    public class var tableCell2SelectedBackgroundColor2: UIColor {
        isDarkThemeEnabled ? darkThemeTableCell2SelectedBackgroundColor2 : .ows_gray15
    }

    @objc
    public class var tableCell2MultiSelectedBackgroundColor: UIColor {
        isDarkThemeEnabled ? darkThemeTableCell2MultiSelectedBackgroundColor : .ows_gray05
    }

    public class var tableCell2PresentedSelectedBackgroundColor: UIColor {
        isDarkThemeEnabled ? darkThemeTableCell2PresentedSelectedBackgroundColor : .ows_gray15
    }

    public class var tableView2BackgroundColor: UIColor {
        isDarkThemeEnabled ? darkThemeTableView2BackgroundColor : .ows_gray10
    }

    public class var tableView2PresentedBackgroundColor: UIColor {
        isDarkThemeEnabled ? darkThemeTableView2PresentedBackgroundColor : .ows_gray10
    }

    public class var tableView2SeparatorColor: UIColor {
        isDarkThemeEnabled ? darkThemeTableView2SeparatorColor : .ows_gray20
    }

    public class var tableView2PresentedSeparatorColor: UIColor {
        isDarkThemeEnabled ? darkThemeTableView2PresentedSeparatorColor : .ows_gray20
    }

    // MARK: - Light Theme Colors

    @objc
    public class var lightThemePrimaryColor: UIColor { .ows_gray90 }

    // MARK: - Dark Theme Colors

    public class var darkThemeBackgroundColor: UIColor { .black }

    public class var darkThemePrimaryColor: UIColor { .ows_gray02 }

    @objc
    public class var darkThemeSecondaryTextAndIconColor: UIColor { .ows_gray25 }

    public class var darkThemeWashColor: UIColor { .ows_gray75 }

    public class var darkThemeNavbarBackgroundColor: UIColor { .black }

    public class var darkThemeNavbarIconColor: UIColor { .ows_gray15 }

    public class var darkThemeTableCell2BackgroundColor: UIColor { .ows_gray90 }

    public class var darkThemeTableCell2PresentedBackgroundColor: UIColor { .ows_gray80 }

    public class var darkThemeTableCell2SelectedBackgroundColor: UIColor { .ows_gray80 }

    public class var darkThemeTableCell2SelectedBackgroundColor2: UIColor { .ows_gray65 }

    public class var darkThemeTableCell2MultiSelectedBackgroundColor: UIColor { .ows_gray75 }

    public class var darkThemeTableCell2PresentedSelectedBackgroundColor: UIColor { .ows_gray75 }

    public class var darkThemeTableView2BackgroundColor: UIColor { .black }

    public class var darkThemeTableView2PresentedBackgroundColor: UIColor { .ows_gray90 }

    public class var darkThemeTableView2SeparatorColor: UIColor { .ows_gray75 }

    public class var darkThemeTableView2PresentedSeparatorColor: UIColor { .ows_gray65 }

    // MARK: - Blur Effect

    public class var barBlurEffect: UIBlurEffect {
        isDarkThemeEnabled ? darkThemeBarBlurEffect : UIBlurEffect(style: .light)
    }

    public class var darkThemeBarBlurEffect: UIBlurEffect { UIBlurEffect(style: .dark) }

    // MARK: - Keyboard

    @objc
    public class var keyboardAppearance: UIKeyboardAppearance {
        isDarkThemeEnabled ? darkThemeKeyboardAppearance : .default
    }

    public class var darkThemeKeyboardAppearance: UIKeyboardAppearance { .dark }

    public class var keyboardBackgroundColor: UIColor {
        isDarkThemeEnabled ? .ows_gray90 : .ows_gray02
    }

    public class var attachmentKeyboardItemBackgroundColor: UIColor {
        isDarkThemeEnabled ? .ows_gray75 : .ows_gray05
    }

    public class var attachmentKeyboardItemImageColor: UIColor {
        isDarkThemeEnabled ? UIColor(rgbHex: 0xd8d8d9) : UIColor(rgbHex: 0x636467)
    }

    // MARK: - Search Bar

    @objc
    public class var barStyle: UIBarStyle {
        isDarkThemeEnabled ? .black : .default
    }

    @objc
    public class var searchFieldBackgroundColor: UIColor { washColor }

    @objc
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
