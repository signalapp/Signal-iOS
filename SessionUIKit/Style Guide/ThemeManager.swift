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
    fileprivate class ThemeApplier {
        enum InfoKey: String {
            case keyPath
            case controlState
        }
        
        private let applyTheme: (Theme) -> ()
        private let info: [AnyHashable]
        private var otherAppliers: [ThemeManager.ThemeApplier]?
        
        init(
            existingApplier: ThemeManager.ThemeApplier?,
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
            self.apply(theme: ThemeManager.currentTheme)
        }
        
        // MARK: - Functions
        
        private func clearingOtherAppliers() -> ThemeManager.ThemeApplier {
            self.otherAppliers = nil
            
            return self
        }
        
        fileprivate func apply(theme: Theme) {
            self.applyTheme(theme)
            
            // If there are otherAppliers stored against this one then trigger those as well
            self.otherAppliers?.forEach { applier in
                applier.applyTheme(theme)
            }
        }
    }
    
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
            if let defaultPrimaryColor: Theme.PrimaryColor = Theme.PrimaryColor(color: currentTheme.colors[.defaultPrimary]) {
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
            
            // If the user enabled the "match system" setting then update the UI if needed
            guard
                matchSystemNightModeSetting &&
                UITraitCollection.current.userInterfaceStyle != ThemeManager.currentTheme.interfaceStyle
            else { return }
            
            traitCollectionDidChange(UITraitCollection.current)
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
    
    public static func applyNavigationStyling() {
        let textPrimary: UIColor = (ThemeManager.currentTheme.colors[.textPrimary] ?? .white)
        
        // Set the `mainWindow.tintColor` for system screens to use the right colour for text
        ThemeManager.mainWindow?.tintColor = textPrimary
        ThemeManager.mainWindow?.rootViewController?.setNeedsStatusBarAppearanceUpdate()
        
        // Update the nav bars to use the right colours
        UINavigationBar.appearance().barTintColor = ThemeManager.currentTheme.colors[.backgroundPrimary]
        UINavigationBar.appearance().isTranslucent = false
        UINavigationBar.appearance().tintColor = textPrimary
        UINavigationBar.appearance().shadowImage = ThemeManager.currentTheme.colors[.backgroundPrimary]?.toImage()
        UINavigationBar.appearance().titleTextAttributes = [
            NSAttributedString.Key.foregroundColor: textPrimary
        ]
        UINavigationBar.appearance().largeTitleTextAttributes = [
            NSAttributedString.Key.foregroundColor: textPrimary
        ]
        
        // Update the bar button item appearance
        UIBarButtonItem.appearance().tintColor = textPrimary

        // Update toolbars to use the right colours
        UIToolbar.appearance().barTintColor = ThemeManager.currentTheme.colors[.backgroundPrimary]
        UIToolbar.appearance().isTranslucent = false
        UIToolbar.appearance().tintColor = textPrimary
        
        // Note: Looks like there were changes to the appearance behaviour in iOS 15, unfortunately
        // this breaks parts of the old 'UINavigationBar.appearance()' logic so we need to do everything
        // again using the new API...
        if #available(iOS 15.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = ThemeManager.currentTheme.colors[.backgroundPrimary]
            appearance.shadowImage = ThemeManager.currentTheme.colors[.backgroundPrimary]?.toImage()
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
        // to force-update the current navigation bar (unfortunately the only way to do this
        // is to remove the nav controller from the view hierarchy and then re-add it)
        let currentNavController: UINavigationController? = {
            var targetViewController: UIViewController? = ThemeManager.mainWindow?.rootViewController
            
            while targetViewController?.presentedViewController != nil {
                targetViewController = targetViewController?.presentedViewController
            }
            
            return (
                (targetViewController as? UINavigationController) ??
                targetViewController?.navigationController
            )
        }()
        
        if
            let navController: UINavigationController = currentNavController,
            let superview: UIView = navController.view.superview,
            !navController.isNavigationBarHidden
        {
            navController.view.removeFromSuperview()
            superview.addSubview(navController.view)
            navController.topViewController?.setNeedsStatusBarAppearanceUpdate()
        }
    }
    
    public static func applyWindowStyling() {
        mainWindow?.overrideUserInterfaceStyle = {
            guard !Storage.shared[.themeMatchSystemDayNightCycle] else {
                return .unspecified
            }
            
            switch ThemeManager.currentTheme.interfaceStyle {
                case .light: return .light
                case .dark, .unspecified: return .dark
                @unknown default: return .dark
            }
        }()
        mainWindow?.backgroundColor = ThemeManager.currentTheme.colors[.backgroundPrimary]
    }
    
    public static func onThemeChange(observer: AnyObject, callback: @escaping (Theme, Theme.PrimaryColor) -> ()) {
        ThemeManager.uiRegistry.setObject(
            ThemeManager.ThemeApplier(
                existingApplier: nil,
                info: []
            ) { theme in callback(theme, ThemeManager.primaryColor) },
            forKey: observer
        )
    }
    
    private static func updateAllUI() {
        ThemeManager.uiRegistry.objectEnumerator()?.forEach { applier in
            (applier as? ThemeApplier)?.apply(theme: currentTheme)
        }
        
        applyNavigationStyling()
        applyWindowStyling()
    }
    
    fileprivate static func set<T: AnyObject>(
        _ view: T,
        keyPath: ReferenceWritableKeyPath<T, UIColor?>,
        to value: ThemeValue?,
        for state: UIControl.State = .normal
    ) {
        ThemeManager.uiRegistry.setObject(
            ThemeManager.ThemeApplier(
                existingApplier: ThemeManager.get(for: view),
                info: [ keyPath ]
            ) { [weak view] theme in
                guard let value: ThemeValue = value else {
                    view?[keyPath: keyPath] = nil
                    return
                }

                view?[keyPath: keyPath] = ThemeManager.resolvedColor(theme.colors[value])
            },
            forKey: view
        )
    }
    
    fileprivate static func set<T: AnyObject>(
        _ view: T,
        keyPath: ReferenceWritableKeyPath<T, CGColor?>,
        to value: ThemeValue?,
        for state: UIControl.State = .normal
    ) {
        ThemeManager.uiRegistry.setObject(
            ThemeManager.ThemeApplier(
                existingApplier: ThemeManager.get(for: view),
                info: [ keyPath ]
            ) { [weak view] theme in
                guard let value: ThemeValue = value else {
                    view?[keyPath: keyPath] = nil
                    return
                }
                
                view?[keyPath: keyPath] = ThemeManager.resolvedColor(theme.colors[value])?.cgColor
            },
            forKey: view
        )
    }
    
    fileprivate static func set<T: AnyObject>(
        _ view: T,
        to applier: ThemeManager.ThemeApplier,
        for state: UIControl.State = .normal
    ) {
        ThemeManager.uiRegistry.setObject(applier, forKey: view)
    }
    
    /// Using a `UIColor(dynamicProvider:)` unfortunately doesn't seem to work properly for some controls (eg. UISwitch) so
    /// since we are already explicitly updating all UI when changing colours & states we just force-resolve the primary colour to avoid
    /// running into these glitches
    fileprivate static func resolvedColor(_ color: UIColor?) -> UIColor? {
        return color?.resolvedColor(with: UITraitCollection())
    }
    
    fileprivate static func get(for view: AnyObject) -> ThemeApplier? {
        return ThemeManager.uiRegistry.object(forKey: view)
    }
}

// MARK: - View Extensions

public extension UIView {
    var themeBackgroundColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.backgroundColor, to: newValue) }
        get { return nil }
    }
    
    var themeTintColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.tintColor, to: newValue) }
        get { return nil }
    }
    
    var themeBorderColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.layer.borderColor, to: newValue) }
        get { return nil }
    }
    
    var themeShadowColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.layer.shadowColor, to: newValue) }
        get { return nil }
    }
}

public extension UILabel {
    var themeTextColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.textColor, to: newValue) }
        get { return nil }
    }
}

public extension UITextView {
    var themeTextColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.textColor, to: newValue) }
        get { return nil }
    }
}

public extension UITextField {
    var themeTextColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.textColor, to: newValue) }
        get { return nil }
    }
}

public extension UIButton {
    func setThemeBackgroundColor(_ value: ThemeValue?, for state: UIControl.State) {
        let keyPath: KeyPath<UIButton, UIImage?> = \.imageView?.image
        
        ThemeManager.set(
            self,
            to: ThemeManager.ThemeApplier(
                existingApplier: ThemeManager.get(for: self),
                info: [
                    keyPath,
                    state.rawValue
                ]
            ) { [weak self] theme in
                guard
                    let value: ThemeValue = value,
                    let color: UIColor = ThemeManager.resolvedColor(theme.colors[value])
                else {
                    self?.setBackgroundImage(nil, for: state)
                    return
                }
                
                self?.setBackgroundImage(color.toImage(), for: state)
            }
        )
    }
    
    func setThemeTitleColor(_ value: ThemeValue?, for state: UIControl.State) {
        let keyPath: KeyPath<UIButton, UIColor?> = \.titleLabel?.textColor
        
        ThemeManager.set(
            self,
            to: ThemeManager.ThemeApplier(
                existingApplier: ThemeManager.get(for: self),
                info: [
                    keyPath,
                    state.rawValue
                ]
            ) { [weak self] theme in
                guard let value: ThemeValue = value else {
                    self?.setTitleColor(nil, for: state)
                    return
                }
                
                self?.setTitleColor(
                    ThemeManager.resolvedColor(theme.colors[value]),
                    for: state
                )
            }
        )
    }
}

public extension UISwitch {
    var themeOnTintColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.onTintColor, to: newValue) }
        get { return nil }
    }
}

public extension UIBarButtonItem {
    var themeTintColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.tintColor, to: newValue) }
        get { return nil }
    }
}

public extension CAShapeLayer {
    var themeStrokeColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.strokeColor, to: newValue) }
        get { return nil }
    }
    
    var themeFillColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.fillColor, to: newValue) }
        get { return nil }
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
