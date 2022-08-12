// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit

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
            to: ThemeApplier(
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
            to: ThemeApplier(
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

public extension UIProgressView {
    var themeProgressTintColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.progressTintColor, to: newValue) }
        get { return nil }
    }
    
    var themeTrackTintColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.trackTintColor, to: newValue) }
        get { return nil }
    }
}

public extension UITableViewRowAction {
    var themeBackgroundColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.backgroundColor, to: newValue) }
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

public extension CALayer {
    var themeBorderColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.borderColor, to: newValue) }
        get { return nil }
    }
    
    var themeShadowColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.shadowColor, to: newValue) }
        get { return nil }
    }
}
