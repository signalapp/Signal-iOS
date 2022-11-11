//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit

@objc
public enum OWSNavigationBarStyle: Int {
    case clear, solid, alwaysDarkAndClear, alwaysDark, `default`

    var forcedStatusBarStyle: UIStatusBarStyle? {
        switch self {
        case .clear:
            return nil
        case .solid:
            return nil
        case .alwaysDarkAndClear:
            return nil
        case .alwaysDark:
            return .lightContent
        case .default:
            return nil
        }
    }
}

@objc
public class OWSNavigationBar: UINavigationBar {

    @objc
    public var fullWidth: CGFloat {
        return superview?.frame.width ?? .zero
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    public static let backgroundBlurMutingFactor: CGFloat = 0.5
    var blurEffectView: UIVisualEffectView?

    override init(frame: CGRect) {
        super.init(frame: frame)

        applyTheme()
    }

    public override var barPosition: UIBarPosition {
        return .topAttached
    }

    public override var frame: CGRect {
        didSet {
            let top = self.convert(CGPoint.zero, from: nil).y
            blurEffectView?.frame = CGRect(
                x: 0,
                y: top,
                width: bounds.width,
                height: bounds.height - top
            )
        }
    }

    // MARK: Theme

    internal var navbarBackgroundColorOverride: UIColor? {
        didSet { applyTheme() }
    }

    private var navbarBackgroundColor: UIColor {
        return navbarBackgroundColorOverride ?? Theme.navbarBackgroundColor
    }

    internal func applyTheme() {
        switch currentStyle {
        case .solid, .default, .alwaysDark, .none:
            self.isTranslucent = !UIAccessibility.isReduceTransparencyEnabled
        case .clear, .alwaysDarkAndClear:
            self.isTranslucent = true
        }

        guard respectsTheme else {
            blurEffectView?.isHidden = true
            return
        }

        if currentStyle == .solid {
            let backgroundImage = UIImage(color: navbarBackgroundColor)
            self.setBackgroundImage(backgroundImage, for: .default)
        } else if UIAccessibility.isReduceTransparencyEnabled {
            blurEffectView?.isHidden = true
            let backgroundImage = UIImage(color: navbarBackgroundColor)
            self.setBackgroundImage(backgroundImage, for: .default)
        } else {
            let blurEffect = Theme.barBlurEffect

            let blurEffectView: UIVisualEffectView = {
                if let existingBlurEffectView = self.blurEffectView {
                    existingBlurEffectView.isHidden = false
                    return existingBlurEffectView
                }

                let blurEffectView = UIVisualEffectView()
                blurEffectView.isUserInteractionEnabled = false

                self.blurEffectView = blurEffectView
                self.insertSubview(blurEffectView, at: 0)

                return blurEffectView
            }()

            blurEffectView.effect = blurEffect

            // remove hairline below bar.
            self.shadowImage = UIImage()

            // On iOS11, despite inserting the blur at 0, other views are later inserted into the navbar behind the blur,
            // so we have to set a zindex to avoid obscuring navbar title/buttons.
            blurEffectView.layer.zPosition = -1

            // Alter the visual effect view's tint to match our background color
            // so the navbar, when over a solid color background matching navbarBackgroundColor,
            // exactly matches the background color. This is brittle, but there is no way to get
            // this behavior from UIVisualEffectView otherwise.
            if let tintingView = blurEffectView.subviews.first(where: {
                String(describing: type(of: $0)) == "_UIVisualEffectSubview"
            }) {
                tintingView.backgroundColor = navbarBackgroundColor.withAlphaComponent(OWSNavigationBar.backgroundBlurMutingFactor)
                self.setBackgroundImage(UIImage(), for: .default)
            } else {
                if #available(iOS 15, *) { owsFailDebug("Check if this still works on new iOS version.") }

                owsFailDebug("Unexpectedly missing visual effect subview")
                // If we can't find the tinting subview (e.g. a new iOS version changed the behavior)
                // We'll make the navbar more translucent by setting a background color.
                let color = navbarBackgroundColor.withAlphaComponent(OWSNavigationBar.backgroundBlurMutingFactor)
                let backgroundImage = UIImage(color: color)
                self.setBackgroundImage(backgroundImage, for: .default)
            }
        }
    }

    private var respectsTheme: Bool {
        switch currentStyle {
        case .none, .default, .solid:
            return true
        case .clear, .alwaysDark, .alwaysDarkAndClear:
            return false
        }
    }

    // MARK: Override Theme

    public private(set) var currentStyle: OWSNavigationBarStyle?
    private var wasDarkTheme: Bool?

    @objc
    internal func setStyle(_ style: OWSNavigationBarStyle, animated: Bool = false) {
        AssertIsOnMainThread()

        guard currentStyle != style || wasDarkTheme != Theme.isDarkThemeEnabled else { return }

        if animated {
            let animation = CATransition()
            animation.duration = 0.35
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.type = .fade
            layer.add(animation, forKey: "ows_fade")
        } else {
            layer.removeAnimation(forKey: "ows_fade")
        }

        let applyDarkThemeOverride = {
            self.barStyle = .black
            self.titleTextAttributes = [NSAttributedString.Key.foregroundColor: Theme.darkThemePrimaryColor]
            self.barTintColor = Theme.darkThemeBackgroundColor.withAlphaComponent(0.6)
            self.tintColor = Theme.darkThemePrimaryColor
        }

        let removeDarkThemeOverride = {
            self.barStyle = Theme.barStyle
            self.titleTextAttributes = [NSAttributedString.Key.foregroundColor: Theme.primaryTextColor]
            self.barTintColor = Theme.backgroundColor.withAlphaComponent(0.6)
            self.tintColor = Theme.primaryTextColor
        }

        let applyTransparentBarOverride = {
            self.blurEffectView?.isHidden = true
            self.clipsToBounds = true

            // Making a toolbar transparent requires setting an empty uiimage
            self.setBackgroundImage(UIImage(), for: .default)
            self.shadowImage = UIImage()
            self.backgroundColor = .clear
        }

        let removeTransparentBarOverride = {
            self.blurEffectView?.isHidden = false
            self.clipsToBounds = false

            self.setBackgroundImage(nil, for: .default)
            self.shadowImage = nil
        }

        let applySolidBarOverride = {
            self.blurEffectView?.isHidden = true
            self.shadowImage = UIImage()
        }

        let removeSecondaryAndSolidBarOverride = {
            self.blurEffectView?.isHidden = false
            self.shadowImage = nil
        }

        currentStyle = style
        wasDarkTheme = Theme.isDarkThemeEnabled

        switch style {
        case .clear:
            removeSecondaryAndSolidBarOverride()
            removeDarkThemeOverride()
            applyTransparentBarOverride()
            applyTheme()
        case .alwaysDarkAndClear:
            removeSecondaryAndSolidBarOverride()
            applyDarkThemeOverride()
            applyTransparentBarOverride()
            applyTheme()
        case .alwaysDark:
            removeSecondaryAndSolidBarOverride()
            removeTransparentBarOverride()
            applyDarkThemeOverride()
            applyTheme()
        case .default:
            removeDarkThemeOverride()
            removeTransparentBarOverride()
            removeSecondaryAndSolidBarOverride()
            applyTheme()
        case .solid:
            removeDarkThemeOverride()
            removeTransparentBarOverride()
            applySolidBarOverride()
            applyTheme()
        }
    }
}
