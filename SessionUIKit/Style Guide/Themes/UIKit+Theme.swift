// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit

public extension UIView {
    var themeBackgroundColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.backgroundColor, to: newValue) }
        get { return nil }
    }
    
    var themeBackgroundColorForced: ForcedThemeValue? {
        set {
            switch newValue {
                case .color(let color): backgroundColor = color
                case .primary(let value, let alpha):
                    guard let alpha: CGFloat = alpha else {
                        backgroundColor = value.color
                        return
                    }
                    
                    backgroundColor = value.color.withAlphaComponent(alpha)
                
                case .theme(let theme, let value, let alpha):
                    guard let alpha: CGFloat = alpha else {
                        backgroundColor = theme.colors[value]
                        return
                    }
                    
                    backgroundColor = theme.colors[value]?.withAlphaComponent(alpha)
                    
                case .none: backgroundColor = nil
            }
        }
        get { return self.backgroundColor.map { .color($0) } }
    }
    
    var themeTintColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.tintColor, to: newValue) }
        get { return nil }
    }
    
    var themeTintColorForced: ForcedThemeValue? {
        set {
            switch newValue {
                case .color(let color): tintColor = color
                case .primary(let value, let alpha):
                    guard let alpha: CGFloat = alpha else {
                        tintColor = value.color
                        return
                    }
                    
                    tintColor = value.color.withAlphaComponent(alpha)
                
                case .theme(let theme, let value, let alpha):
                    guard let alpha: CGFloat = alpha else {
                        tintColor = theme.colors[value]
                        return
                    }
                    
                    tintColor = theme.colors[value]?.withAlphaComponent(alpha)
                    
                case .none: tintColor = nil
            }
        }
        get { return self.tintColor.map { .color($0) } }
    }
    
    var themeBorderColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.layer.borderColor, to: newValue) }
        get { return nil }
    }
    
    var themeBorderColorForced: ForcedThemeValue? {
        set {
            switch newValue {
                case .color(let color): layer.borderColor = color.cgColor
                case .primary(let value, let alpha):
                    guard let alpha: CGFloat = alpha else {
                        layer.borderColor = value.color.cgColor
                        return
                    }
                    
                    layer.borderColor = value.color.withAlphaComponent(alpha).cgColor
                
                case .theme(let theme, let value, let alpha):
                    guard let alpha: CGFloat = alpha else {
                        layer.borderColor = theme.colors[value]?.cgColor
                        return
                    }
                    
                    layer.borderColor = theme.colors[value]?.withAlphaComponent(alpha).cgColor
                    
                case .none: layer.borderColor = nil
            }
        }
        get { return nil }
    }
    
    var themeShadowColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.layer.shadowColor, to: newValue) }
        get { return nil }
    }
    
    var themeShadowColorForced: ForcedThemeValue? {
        set {
            switch newValue {
                case .color(let color): layer.shadowColor = color.cgColor
                case .primary(let value, let alpha):
                    guard let alpha: CGFloat = alpha else {
                        layer.shadowColor = value.color.cgColor
                        return
                    }
                    
                    layer.shadowColor = value.color.withAlphaComponent(alpha).cgColor
                
                case .theme(let theme, let value, let alpha):
                    guard let alpha: CGFloat = alpha else {
                        layer.shadowColor = theme.colors[value]?.cgColor
                        return
                    }
                    
                    layer.shadowColor = theme.colors[value]?.withAlphaComponent(alpha).cgColor
                    
                case .none: layer.shadowColor = nil
            }
        }
        get { return self.layer.shadowColor.map { .color(UIColor(cgColor: $0)) } }
    }
}

public extension UILabel {
    var themeTextColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.textColor, to: newValue) }
        get { return nil }
    }
    
    var themeTextColorForced: ForcedThemeValue? {
        set {
            switch newValue {
                case .color(let color): textColor = color
                case .primary(let value, let alpha):
                    guard let alpha: CGFloat = alpha else {
                        textColor = value.color
                        return
                    }
                    
                    textColor = value.color.withAlphaComponent(alpha)
                
                case .theme(let theme, let value, let alpha):
                    guard let alpha: CGFloat = alpha else {
                        textColor = theme.colors[value]
                        return
                    }
                    
                    textColor = theme.colors[value]?.withAlphaComponent(alpha)
                    
                case .none: textColor = nil
            }
        }
        get { return self.textColor.map { .color($0) } }
    }
}

public extension UITextView {
    var themeTextColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.textColor, to: newValue) }
        get { return nil }
    }
    
    var themeTextColorForced: ForcedThemeValue? {
        set {
            switch newValue {
                case .color(let color): textColor = color
                case .primary(let value, let alpha):
                    guard let alpha: CGFloat = alpha else {
                        textColor = value.color
                        return
                    }
                    
                    textColor = value.color.withAlphaComponent(alpha)
                
                case .theme(let theme, let value, let alpha):
                    guard let alpha: CGFloat = alpha else {
                        textColor = theme.colors[value]
                        return
                    }
                    
                    textColor = theme.colors[value]?.withAlphaComponent(alpha)
                    
                case .none: textColor = nil
            }
        }
        get { return self.textColor.map { .color($0) } }
    }
}

public extension UITextField {
    var themeTextColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.textColor, to: newValue) }
        get { return nil }
    }
    
    var themeTextColorForced: ForcedThemeValue? {
        set {
            switch newValue {
                case .color(let color): textColor = color
                case .primary(let value, let alpha):
                    guard let alpha: CGFloat = alpha else {
                        textColor = value.color
                        return
                    }
                    
                    textColor = value.color.withAlphaComponent(alpha)
                
                case .theme(let theme, let value, let alpha):
                    guard let alpha: CGFloat = alpha else {
                        textColor = theme.colors[value]
                        return
                    }
                    
                    textColor = theme.colors[value]?.withAlphaComponent(alpha)
                    
                case .none: textColor = nil
            }
        }
        get { return self.textColor.map { .color($0) } }
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
    
    func setThemeBackgroundColorForced(_ newValue: ForcedThemeValue?, for state: UIControl.State) {
        switch newValue {
            case .color(let color): self.setBackgroundImage(color.toImage(), for: state)
            case .primary(let value, let alpha):
                guard let alpha: CGFloat = alpha else {
                    self.setBackgroundImage(value.color.toImage(), for: state)
                    return
                }
                
                self.setBackgroundImage(value.color.withAlphaComponent(alpha).toImage(), for: state)
                
            case .theme(let theme, let value, let alpha):
                guard let alpha: CGFloat = alpha else {
                    self.setBackgroundImage(theme.colors[value]?.toImage(), for: state)
                    return
                }

                self.setBackgroundImage(theme.colors[value]?.withAlphaComponent(alpha).toImage(), for: state)
            
            case .none: self.setBackgroundImage(nil, for: state)
        }
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
    
    func setThemeTitleColorForced(_ newValue: ForcedThemeValue?, for state: UIControl.State) {
        switch newValue {
            case .color(let color): self.setTitleColor(color, for: state)
            case .primary(let value, let alpha):
                guard let alpha: CGFloat = alpha else {
                    self.setTitleColor(value.color, for: state)
                    return
                }
                
                self.setTitleColor(value.color.withAlphaComponent(alpha), for: state)
                
            case .theme(let theme, let value, let alpha):
                guard let alpha: CGFloat = alpha else {
                    self.setTitleColor(theme.colors[value], for: state)
                    return
                }

                self.setTitleColor(theme.colors[value]?.withAlphaComponent(alpha), for: state)
            
            case .none: self.setTitleColor(nil, for: state)
        }
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
    
    var themeProgressTintColorForced: ForcedThemeValue? {
        set {
            switch newValue {
                case .color(let color): progressTintColor = color
                case .primary(let value, let alpha):
                    guard let alpha: CGFloat = alpha else {
                        progressTintColor = value.color
                        return
                    }
                    
                    progressTintColor = value.color.withAlphaComponent(alpha)
                
                case .theme(let theme, let value, let alpha):
                    guard let alpha: CGFloat = alpha else {
                        progressTintColor = theme.colors[value]
                        return
                    }

                    progressTintColor = theme.colors[value]?.withAlphaComponent(alpha)
                
                case .none: progressTintColor = nil
            }
        }
        get { return self.progressTintColor.map { .color($0) } }
    }
    
    var themeTrackTintColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.trackTintColor, to: newValue) }
        get { return nil }
    }
}

public extension UISlider {
    var themeMinimumTrackTintColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.minimumTrackTintColor, to: newValue) }
        get { return nil }
    }
    
    var themeMaximumTrackTintColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.maximumTrackTintColor, to: newValue) }
        get { return nil }
    }
}

public extension UIToolbar {
    var themeBarTintColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.barTintColor, to: newValue) }
        get { return nil }
    }
}

public extension UIContextualAction {
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
    
    var themeStrokeColorForced: ForcedThemeValue? {
        set {
            switch newValue {
                case .color(let color): strokeColor = color.cgColor
                case .primary(let value, let alpha):
                    guard let alpha: CGFloat = alpha else {
                        strokeColor = value.color.cgColor
                        return
                    }
                    
                    strokeColor = value.color.withAlphaComponent(alpha).cgColor
                
                case .theme(let theme, let value, let alpha):
                    guard let alpha: CGFloat = alpha else {
                        strokeColor = theme.colors[value]?.cgColor
                        return
                    }

                    strokeColor = theme.colors[value]?.withAlphaComponent(alpha).cgColor
                
                case .none: strokeColor = nil
            }
        }
        get { return self.strokeColor.map { .color(UIColor(cgColor: $0)) } }
    }
    
    var themeFillColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.fillColor, to: newValue) }
        get { return nil }
    }
    
    var themeFillColorForced: ForcedThemeValue? {
        set {
            switch newValue {
                case .color(let color): fillColor = color.cgColor
                case .primary(let value, let alpha):
                    guard let alpha: CGFloat = alpha else {
                        fillColor = value.color.cgColor
                        return
                    }
                    
                    fillColor = value.color.withAlphaComponent(alpha).cgColor
                
                case .theme(let theme, let value, let alpha):
                    guard let alpha: CGFloat = alpha else {
                        fillColor = theme.colors[value]?.cgColor
                        return
                    }

                    fillColor = theme.colors[value]?.withAlphaComponent(alpha).cgColor
                
                case .none: fillColor = nil
            }
        }
        get { return self.fillColor.map { .color(UIColor(cgColor: $0)) } }
    }
}

public extension CALayer {
    var themeBackgroundColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.backgroundColor, to: newValue) }
        get { return nil }
    }
    
    var themeBackgroundColorForced: ForcedThemeValue? {
        set {
            switch newValue {
                case .color(let color): backgroundColor = color.cgColor
                case .primary(let value, let alpha):
                    guard let alpha: CGFloat = alpha else {
                        backgroundColor = value.color.cgColor
                        return
                    }
                    
                    backgroundColor = value.color.withAlphaComponent(alpha).cgColor
                    
                case .theme(let theme, let value, let alpha):
                    guard let alpha: CGFloat = alpha else {
                        backgroundColor = theme.colors[value]?.cgColor
                        return
                    }
                    
                    backgroundColor = theme.colors[value]?.withAlphaComponent(alpha).cgColor
                    
                case .none: backgroundColor = nil
            }
        }
        get { return self.backgroundColor.map { .color(UIColor(cgColor: $0)) } }
    }
    
    var themeBorderColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.borderColor, to: newValue) }
        get { return nil }
    }
    
    var themeShadowColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.shadowColor, to: newValue) }
        get { return nil }
    }
}

public extension CATextLayer {
    var themeForegroundColor: ThemeValue? {
        set { ThemeManager.set(self, keyPath: \.foregroundColor, to: newValue) }
        get { return nil }
    }
    
    var themeForegroundColorForced: ForcedThemeValue? {
        set {
            switch newValue {
                case .color(let color): foregroundColor = color.cgColor
                case .primary(let value, let alpha):
                    guard let alpha: CGFloat = alpha else {
                        foregroundColor = value.color.cgColor
                        return
                    }
                    
                    foregroundColor = value.color.withAlphaComponent(alpha).cgColor
                    
                case .theme(let theme, let value, let alpha):
                    guard let alpha: CGFloat = alpha else {
                        foregroundColor = theme.colors[value]?.cgColor
                        return
                    }

                    foregroundColor = theme.colors[value]?.withAlphaComponent(alpha).cgColor
                
                case .none: foregroundColor = nil
            }
        }
        get { return self.foregroundColor.map { .color(UIColor(cgColor: $0)) } }
    }
}

public extension NSMutableAttributedString {
    func addThemeAttribute(_ attribute: ForcedThemeAttribute, range: NSRange) {
        self.addAttribute(attribute.key, value: attribute.value, range: range)
    }
}
