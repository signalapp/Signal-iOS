// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
import SessionUtilitiesKit

// MARK: - Preferences

public extension Setting.EnumKey {
    /// Controls what theme should be used
    static let theme: Setting.EnumKey = "selectedTheme"
    
    /// Controls what primary color should be used for the theme
    static let themePrimaryColor: Setting.EnumKey = "selectedThemePrimaryColor"
}

public extension Setting.BoolKey {
    /// A flag indicating whether the app should match system day/night settings
    static let themeMatchSystemDayNightCycle: Setting.BoolKey = "themeMatchSystemDayNightCycle"
}

// MARK: - ThemeManager

public enum ThemeManager {
    private static var hasSetInitialSystemTrait: Bool = false
    
    /// **Note:** Using `weakToStrongObjects` means that the value types will continue to be maintained until the map table resizes
    /// itself (ie. until a new UI element is registered to the table)
    ///
    /// Unfortunately if we don't do this the `ThemeApplier` is immediately deallocated and we can't use it to update the theme
    private static var uiRegistry: NSMapTable<AnyObject, ThemeApplier> = NSMapTable.weakToStrongObjects()
    
    public static var currentTheme: Theme = {
        Storage.shared[.theme].defaulting(to: Theme.classicDark)
    }() {
        didSet {
            // Only update if it was changed
            guard oldValue != currentTheme else { return }
            
            Storage.shared.writeAsync { db in
                db[.theme] = currentTheme
            }
            
            // Only trigger the UI update if the primary colour wasn't changed (otherwise we'd be doing
            // an extra UI update
            if let defaultPrimaryColor: Theme.PrimaryColor = Theme.PrimaryColor(color: currentTheme.color(for: .defaultPrimary)) {
                guard primaryColor == defaultPrimaryColor else {
                    ThemeManager.primaryColor = defaultPrimaryColor
                    return
                }
            }
            
            updateAllUI()
        }
    }
    
    public static var primaryColor: Theme.PrimaryColor = {
        Storage.shared[.themePrimaryColor].defaulting(to: Theme.PrimaryColor.green)
    }() {
        didSet {
            // Only update if it was changed
            guard oldValue != primaryColor else { return }
            
            Storage.shared.writeAsync { db in
                db[.themePrimaryColor] = primaryColor
            }
            
            updateAllUI()
        }
    }
    
    public static var matchSystemNightModeSetting: Bool = {
        Storage.shared[.themeMatchSystemDayNightCycle]
    }() {
        didSet {
            // Only update if it was changed
            guard oldValue != matchSystemNightModeSetting else { return }
            
            Storage.shared.writeAsync { db in
                db[.themeMatchSystemDayNightCycle] = matchSystemNightModeSetting
            }
            
            // Note: We have to trigger this directly or the 'TraitObservingWindow' won't actually
            // trigger the trait change if the app launched with this setting switched off
            
            // Note: We need to set this to 'unspecified' to force the UI to properly update as the
            // 'TraitObservingWindow' won't actually trigger the trait change otherwise
            DispatchQueue.main.async {
                self.mainWindow?.overrideUserInterfaceStyle = .unspecified
            }
        }
    }
    
    // When this gets set we need to update the UI to ensure the global appearance stuff is set
    // correctly on launch
    public static weak var mainWindow: UIWindow? {
        didSet { updateAllUI() }
    }
    
    // MARK: - Functions
    
    public static func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        let currentUserInterfaceStyle: UIUserInterfaceStyle = UITraitCollection.current.userInterfaceStyle
        
        // Only trigger updates if the style changed and the device is set to match the system style
        guard
            currentUserInterfaceStyle != ThemeManager.currentTheme.interfaceStyle,
            ThemeManager.matchSystemNightModeSetting
        else { return }
        
        // Swap to the appropriate light/dark mode
        switch (currentUserInterfaceStyle, ThemeManager.currentTheme) {
            case (.light, .classicDark): ThemeManager.currentTheme = .classicLight
            case (.light, .oceanDark): ThemeManager.currentTheme = .oceanLight
            case (.dark, .classicLight): ThemeManager.currentTheme = .classicDark
            case (.dark, .oceanLight): ThemeManager.currentTheme = .oceanDark
            default: break
        }
    }
    
    public static func applySavedTheme() {
        ThemeManager.primaryColor = Storage.shared[.themePrimaryColor].defaulting(to: Theme.PrimaryColor.green)
        ThemeManager.currentTheme = Storage.shared[.theme].defaulting(to: Theme.classicDark)
    }
    
    public static func applyNavigationStyling() {
        guard Thread.isMainThread else {
            return DispatchQueue.main.async { applyNavigationStyling() }
        }
        
        let textPrimary: UIColor = (ThemeManager.currentTheme.color(for: .textPrimary) ?? .white)
        
        // Set the `mainWindow.tintColor` for system screens to use the right colour for text
        ThemeManager.mainWindow?.tintColor = textPrimary
        ThemeManager.mainWindow?.rootViewController?.setNeedsStatusBarAppearanceUpdate()
        
        // Update the nav bars to use the right colours (we default to the 'primary' value)
        UINavigationBar.appearance().barTintColor = ThemeManager.currentTheme.color(for: .backgroundPrimary)
        UINavigationBar.appearance().isTranslucent = false
        UINavigationBar.appearance().tintColor = textPrimary
        UINavigationBar.appearance().shadowImage = ThemeManager.currentTheme.color(for: .backgroundPrimary)?.toImage()
        UINavigationBar.appearance().titleTextAttributes = [
            NSAttributedString.Key.foregroundColor: textPrimary
        ]
        UINavigationBar.appearance().largeTitleTextAttributes = [
            NSAttributedString.Key.foregroundColor: textPrimary
        ]
        
        // Update the bar button item appearance
        UIBarButtonItem.appearance().tintColor = textPrimary

        // Update toolbars to use the right colours
        UIToolbar.appearance().barTintColor = ThemeManager.currentTheme.color(for: .backgroundPrimary)
        UIToolbar.appearance().isTranslucent = false
        UIToolbar.appearance().tintColor = textPrimary
        
        // Note: Looks like there were changes to the appearance behaviour in iOS 15, unfortunately
        // this breaks parts of the old 'UINavigationBar.appearance()' logic so we need to do everything
        // again using the new API...
        if #available(iOS 15.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = ThemeManager.currentTheme.color(for: .backgroundPrimary)
            appearance.shadowImage = ThemeManager.currentTheme.color(for: .backgroundPrimary)?.toImage()
            appearance.titleTextAttributes = [
                NSAttributedString.Key.foregroundColor: textPrimary
            ]
            appearance.largeTitleTextAttributes = [
                NSAttributedString.Key.foregroundColor: textPrimary
            ]
            
            // Apply the button item appearance as well
            let barButtonItemAppearance = UIBarButtonItemAppearance(style: .plain)
            barButtonItemAppearance.normal.titleTextAttributes = [ .foregroundColor: textPrimary ]
            barButtonItemAppearance.disabled.titleTextAttributes = [ .foregroundColor: textPrimary ]
            barButtonItemAppearance.highlighted.titleTextAttributes = [ .foregroundColor: textPrimary ]
            barButtonItemAppearance.focused.titleTextAttributes = [ .foregroundColor: textPrimary ]
            appearance.buttonAppearance = barButtonItemAppearance
            appearance.backButtonAppearance = barButtonItemAppearance
            appearance.doneButtonAppearance = barButtonItemAppearance
            
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
        }
        
        // Note: 'UINavigationBar.appearance' only affects newly created nav bars so we need
        // to force-update any current navigation bar (unfortunately the only way to do this
        // is to remove the nav controller from the view hierarchy and then re-add it)
        func updateIfNeeded(viewController: UIViewController?) {
            guard let viewController: UIViewController = viewController else { return }
            guard
                let navController: UINavigationController = ((viewController as? UINavigationController) ?? viewController.navigationController),
                let superview: UIView = navController.view.superview,
                !navController.isNavigationBarHidden
            else {
                updateIfNeeded(viewController:
                    viewController.presentedViewController ??
                    viewController.navigationController?.presentedViewController
                )
                return
            }
            
            // Apply non-primary styling if needed
            applyNavigationStylingIfNeeded(to: viewController)
            
            // Re-attach to the UI
            navController.view.removeFromSuperview()
            superview.addSubview(navController.view)
            navController.topViewController?.setNeedsStatusBarAppearanceUpdate()
            
            // Recurse through the rest of the UI
            updateIfNeeded(viewController:
                viewController.presentedViewController ??
                viewController.navigationController?.presentedViewController
            )
        }
        
        updateIfNeeded(viewController: ThemeManager.mainWindow?.rootViewController)
    }
    
    public static func applyNavigationStylingIfNeeded(to viewController: UIViewController) {
        // Will use the 'primary' style for all other cases
        guard
            let navController: UINavigationController = ((viewController as? UINavigationController) ?? viewController.navigationController),
            let navigationBackground: ThemeValue = (navController.viewControllers.first as? ThemedNavigation)?.navigationBackground
        else { return }
        
        navController.navigationBar.barTintColor = ThemeManager.currentTheme.color(for: navigationBackground)
        navController.navigationBar.shadowImage = ThemeManager.currentTheme.color(for: navigationBackground)?.toImage()
        
        // Note: Looks like there were changes to the appearance behaviour in iOS 15, unfortunately
        // this breaks parts of the old 'UINavigationBar.appearance()' logic so we need to do everything
        // again using the new API...
        if #available(iOS 15.0, *) {
            let textPrimary: UIColor = (ThemeManager.currentTheme.color(for: .textPrimary) ?? .white)
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = ThemeManager.currentTheme.color(for: navigationBackground)
            appearance.shadowImage = ThemeManager.currentTheme.color(for: navigationBackground)?.toImage()
            appearance.titleTextAttributes = [
                NSAttributedString.Key.foregroundColor: textPrimary
            ]
            appearance.largeTitleTextAttributes = [
                NSAttributedString.Key.foregroundColor: textPrimary
            ]
            
            navController.navigationBar.standardAppearance = appearance
            navController.navigationBar.scrollEdgeAppearance = appearance
        }
    }
    
    public static func applyWindowStyling() {
        guard Thread.isMainThread else {
            return DispatchQueue.main.async { applyWindowStyling() }
        }
        
        mainWindow?.overrideUserInterfaceStyle = {
            guard !ThemeManager.matchSystemNightModeSetting else { return .unspecified }
            
            switch ThemeManager.currentTheme.interfaceStyle {
                case .light: return .light
                case .dark, .unspecified: return .dark
                @unknown default: return .dark
            }
        }()
        mainWindow?.backgroundColor = ThemeManager.currentTheme.color(for: .backgroundPrimary)
    }
    
    public static func onThemeChange(observer: AnyObject, callback: @escaping (Theme, Theme.PrimaryColor) -> ()) {
        ThemeManager.uiRegistry.setObject(
            ThemeApplier(
                existingApplier: ThemeManager.get(for: observer),
                info: []
            ) { theme in callback(theme, ThemeManager.primaryColor) },
            forKey: observer
        )
    }
    
    private static func updateAllUI() {
        guard Thread.isMainThread else {
            return DispatchQueue.main.async { updateAllUI() }
        }
        
        ThemeManager.uiRegistry.objectEnumerator()?.forEach { applier in
            (applier as? ThemeApplier)?.apply(theme: currentTheme)
        }
        
        applyNavigationStyling()
        applyWindowStyling()
        
        if !hasSetInitialSystemTrait {
            traitCollectionDidChange(nil)
            hasSetInitialSystemTrait = true
        }
    }
    
    internal static func set<T: AnyObject>(
        _ view: T,
        keyPath: ReferenceWritableKeyPath<T, UIColor?>,
        to value: ThemeValue?
    ) {
        ThemeManager.uiRegistry.setObject(
            ThemeApplier(
                existingApplier: ThemeManager.get(for: view),
                info: [ keyPath ]
            ) { [weak view] theme in
                guard let value: ThemeValue = value else {
                    view?[keyPath: keyPath] = nil
                    return
                }

                view?[keyPath: keyPath] = ThemeManager.resolvedColor(theme.color(for: value))
            },
            forKey: view
        )
    }
    
    internal static func remove<T: AnyObject>(
        _ view: T,
        keyPath: ReferenceWritableKeyPath<T, UIColor?>
    ) {
        // Note: Need to explicitly remove (setting to 'nil' won't actually remove it)
        guard let updatedApplier: ThemeApplier = ThemeManager.get(for: view)?.removing(allWith: keyPath) else {
            ThemeManager.uiRegistry.removeObject(forKey: view)
            return
        }
        
        ThemeManager.uiRegistry.setObject(updatedApplier, forKey: view)
    }
    
    internal static func set<T: AnyObject>(
        _ view: T,
        keyPath: ReferenceWritableKeyPath<T, CGColor?>,
        to value: ThemeValue?
    ) {
        ThemeManager.uiRegistry.setObject(
            ThemeApplier(
                existingApplier: ThemeManager.get(for: view),
                info: [ keyPath ]
            ) { [weak view] theme in
                guard let value: ThemeValue = value else {
                    view?[keyPath: keyPath] = nil
                    return
                }
                
                view?[keyPath: keyPath] = ThemeManager.resolvedColor(theme.color(for: value))?.cgColor
            },
            forKey: view
        )
    }
    
    internal static func remove<T: AnyObject>(
        _ view: T,
        keyPath: ReferenceWritableKeyPath<T, CGColor?>
    ) {
        ThemeManager.uiRegistry.setObject(
            ThemeManager.get(for: view)?
                .removing(allWith: keyPath),
            forKey: view
        )
    }
    
    internal static func set<T: AnyObject>(
        _ view: T,
        to applier: ThemeApplier?
    ) {
        ThemeManager.uiRegistry.setObject(applier, forKey: view)
    }
    
    /// Using a `UIColor(dynamicProvider:)` unfortunately doesn't seem to work properly for some controls (eg. UISwitch) so
    /// since we are already explicitly updating all UI when changing colours & states we just force-resolve the primary colour to avoid
    /// running into these glitches
    internal static func resolvedColor(_ color: UIColor?) -> UIColor? {
        return color?.resolvedColor(with: UITraitCollection())
    }
    
    internal static func get(for view: AnyObject) -> ThemeApplier? {
        return ThemeManager.uiRegistry.object(forKey: view)
    }
}

// MARK: - ThemeApplier

internal class ThemeApplier {
    enum InfoKey: String {
        case keyPath
        case controlState
    }
    
    private let applyTheme: (Theme) -> ()
    private let info: [AnyHashable]
    private var otherAppliers: [ThemeApplier]?
    
    init(
        existingApplier: ThemeApplier?,
        info: [AnyHashable],
        applyTheme: @escaping (Theme) -> ()
    ) {
        self.applyTheme = applyTheme
        self.info = info
        
        // Store any existing "appliers" (removing their 'otherApplier' references to prevent
        // loops and excluding any which match the current "info" as they should be replaced
        // by this applier)
        self.otherAppliers = [existingApplier]
            .appending(contentsOf: existingApplier?.otherAppliers)
            .compactMap { $0?.clearingOtherAppliers() }
            .filter { $0.info != info }
        
        // Automatically apply the theme immediately
        self.apply(theme: ThemeManager.currentTheme, isInitialApplication: true)
    }
    
    // MARK: - Functions
    
    public func removing(allWith info: AnyHashable) -> ThemeApplier? {
        let remainingAppliers: [ThemeApplier] = [self]
            .appending(contentsOf: self.otherAppliers)
            .filter { applier in !applier.info.contains(info) }
        
        guard !remainingAppliers.isEmpty else { return nil }
        guard remainingAppliers.count != ((self.otherAppliers ?? []).count + 1) else { return self }
        
        // Remove the 'otherAppliers' references on self
        self.otherAppliers = nil
        
        // Attach the 'otherAppliers' to the new first remaining applier (just in case self
        // was removed)
        let firstApplier: ThemeApplier? = remainingAppliers.first
        firstApplier?.otherAppliers = Array(remainingAppliers.suffix(from: 1))
        
        return firstApplier
    }
    
    private func clearingOtherAppliers() -> ThemeApplier {
        self.otherAppliers = nil
        
        return self
    }
    
    fileprivate func apply(theme: Theme, isInitialApplication: Bool = false) {
        self.applyTheme(theme)
        
        // For the initial application of a ThemeApplier we don't want to apply the other
        // appliers (they should have already been applied so doing so is redundant
        guard !isInitialApplication else { return }
        
        // If there are otherAppliers stored against this one then trigger those as well
        self.otherAppliers?.forEach { applier in
            applier.applyTheme(theme)
        }
    }
}

// MARK: - Convenience Extensions

extension Array {
    fileprivate func appending(contentsOf other: [Element]?) -> [Element] {
        guard let other: [Element] = other else { return self }
        
        var updatedArray: [Element] = self
        updatedArray.append(contentsOf: other)
        return updatedArray
    }
}
