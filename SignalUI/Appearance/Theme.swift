//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

public extension Notification.Name {
    static let themeDidChange = Notification.Name("ThemeDidChangeNotification")
}

public final class Theme {

    private static var shared = Theme(themeDataStore: ThemeDataStore())

    private let themeDataStore: ThemeDataStore
    private init(themeDataStore: ThemeDataStore) {
        self.themeDataStore = themeDataStore
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

    public class func setupSignalAppearance() {
        let primaryIconColor = UIColor(
            light: .ows_gray75,
            lightHighContrast: .ows_gray75,
            dark: .ows_gray15,
            darkHighContrast: .ows_gray15,
        )
        UINavigationBar.appearance().barTintColor = UIColor.Signal.background
        UINavigationBar.appearance().tintColor = primaryIconColor
        UIToolbar.appearance().barTintColor = UIColor.Signal.background
        UIToolbar.appearance().tintColor = primaryIconColor

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

        UITableViewCell.appearance().tintColor = primaryIconColor
        UIToolbar.appearance().tintColor = .ows_accentBlue

        // If we set NSShadowAttributeName, the NSForegroundColorAttributeName value is ignored.
        UINavigationBar.appearance().titleTextAttributes = [
            .foregroundColor: UIColor.Signal.label,
        ]

        let cursorColor = UIColor(
            light: .Signal.accent,
            lightHighContrast: .Signal.accent,
            dark: .white,
            darkHighContrast: .white,
        )
        UITextView.appearance(whenContainedInInstancesOf: [OWSNavigationController.self]).tintColor = cursorColor
        UITextField.appearance(whenContainedInInstancesOf: [OWSNavigationController.self]).tintColor = cursorColor
    }

    // MARK: - Theme Mode

    public static var isDarkThemeEnabled: Bool { shared.isDarkThemeEnabled }

    public class func getOrFetchCurrentMode() -> ThemeDataStore.Appearance {
        return shared.getOrFetchCurrentMode()
    }

    public class func setCurrentMode(_ mode: ThemeDataStore.Appearance) {
        shared.setCurrentMode(mode)
    }

    public class func performWithModeAsCurrent(_ mode: ThemeDataStore.Appearance, _ operation: () -> Void) {
        shared.performWithModeAsCurrent(mode, operation)
    }

    private func performWithModeAsCurrent(_ mode: ThemeDataStore.Appearance, _ operation: () -> Void) {
        let previousMode = cachedCurrentMode
        defer { cachedCurrentMode = previousMode }
        cachedCurrentMode = mode
        operation()
    }

    private var cachedIsDarkThemeEnabled: Bool?
    private var cachedCurrentMode: ThemeDataStore.Appearance?

    public static var shareExtensionInterfaceStyleOverride: UIUserInterfaceStyle = .unspecified {
        didSet {
            owsPrecondition(
                CurrentAppContext().isShareExtension,
                "Must only be set in the share extension!",
            )

            if oldValue != shareExtensionInterfaceStyleOverride {
                shared.themeDidChange()
            }
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
            return switch Self.shareExtensionInterfaceStyleOverride {
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

    private func getOrFetchCurrentMode() -> ThemeDataStore.Appearance {
        if let cachedCurrentMode {
            return cachedCurrentMode
        }

        guard AppReadinessObjcBridge.isAppReady else {
            return defaultMode
        }

        var currentMode: ThemeDataStore.Appearance = .system
        SSKEnvironment.shared.databaseStorageRef.read { tx in
            currentMode = self.themeDataStore.getCurrentMode(tx: tx)
        }

        cachedCurrentMode = currentMode

        return currentMode
    }

    public func setCurrentMode(_ mode: ThemeDataStore.Appearance) {
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
        SSKEnvironment.shared.databaseStorageRef.asyncWrite { tx in
            self.themeDataStore.setCurrentMode(mode, tx: tx)
        }

        if previousMode != mode {
            themeDidChange()
        }
    }

    private var defaultMode: ThemeDataStore.Appearance {
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
            : lightThemeBackgroundColor
    }

    public class var secondaryBackgroundColor: UIColor {
        isDarkThemeEnabled
            ? darkThemeSecondaryBackgroundColor
            : UIColor.Signal.secondaryBackground.resolvedColor(with: lightTraitCollection)
    }

    public class var darkThemeSecondaryBackgroundColor: UIColor {
        UIColor.Signal.secondaryBackground.resolvedColor(with: darkTraitCollection)
    }

    public static var actionSheetBackgroundColor: UIColor {
        isDarkThemeEnabled ? .ows_gray75 : .ows_white
    }

    public class var washColor: UIColor {
        isDarkThemeEnabled ? darkThemeWashColor : .ows_gray05
    }

    public class var primaryTextColor: UIColor {
        isDarkThemeEnabled ? darkThemePrimaryColor : lightThemePrimaryColor
    }

    public class var primaryIconColor: UIColor {
        if #available(iOS 26, *) {
            return primaryTextColor
        }
        return legacyPrimaryIconColor
    }

    public class var legacyPrimaryIconColor: UIColor {
        isDarkThemeEnabled ? darkThemeLegacyPrimaryIconColor : lightThemeLegacyPrimaryIconColor
    }

    public class var secondaryTextAndIconColor: UIColor {
        isDarkThemeEnabled ? darkThemeSecondaryTextAndIconColor : lightThemeSecondaryTextAndIconColor
    }

    public class var navbarBackgroundColor: UIColor {
        backgroundColor
    }

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
        UIColor(
            light: UIColor(rgbHex: 0xD4D4D6),
            lightHighContrast: UIColor(rgbHex: 0xC6C6CA),
            dark: UIColor(rgbHex: 0x3A3A3D),
            darkHighContrast: UIColor(rgbHex: 0x525257),
        )
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

    public class var lightThemeBackgroundColor: UIColor {
        UIColor.Signal.background.resolvedColor(with: lightTraitCollection)
    }

    public class var lightThemePrimaryColor: UIColor {
        UIColor.Signal.label.resolvedColor(with: lightTraitCollection)
    }

    public class var lightThemeLegacyPrimaryIconColor: UIColor { .ows_gray75 }

    public class var lightThemeSecondaryTextAndIconColor: UIColor {
        UIColor.Signal.secondaryLabel.resolvedColor(with: lightTraitCollection)
    }

    // MARK: - Dark Theme Colors

    public class var darkThemeBackgroundColor: UIColor {
        UIColor.Signal.background.resolvedColor(with: darkTraitCollection)
    }

    public class var darkThemePrimaryColor: UIColor {
        UIColor.Signal.label.resolvedColor(with: darkTraitCollection)
    }

    public class var darkThemeLegacyPrimaryIconColor: UIColor { .ows_gray15 }

    public class var darkThemeSecondaryTextAndIconColor: UIColor {
        UIColor.Signal.secondaryLabel.resolvedColor(with: darkTraitCollection)
    }

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
