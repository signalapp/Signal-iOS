//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

@objc
public class OWSNavigationBar: UINavigationBar {

    @objc
    public let navbarWithoutStatusHeight: CGFloat = 44

    @objc
    public var statusBarHeight: CGFloat {
        return CurrentAppContext().statusBarHeight
    }

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

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(themeDidChange),
                                               name: .ThemeDidChange,
                                               object: nil)
    }

    // MARK: Theme

    public var navbarBackgroundColorOverride: UIColor? {
        didSet { applyTheme() }
    }

    var navbarBackgroundColor: UIColor {
        if let navbarBackgroundColorOverride = navbarBackgroundColorOverride { return navbarBackgroundColorOverride }
        return Theme.navbarBackgroundColor
    }

    private func applyTheme() {
        guard respectsTheme else {
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

                // navbar frame doesn't account for statusBar, so, same as the built-in navbar background, we need to exceed
                // the navbar bounds to have the blur extend up and behind the status bar.
                blurEffectView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: -statusBarHeight, left: 0, bottom: 0, right: 0))

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

    @objc
    public func themeDidChange() {
        Logger.debug("")
        applyTheme()
    }

    @objc
    public var respectsTheme: Bool = true {
        didSet {
            themeDidChange()
        }
    }

    // MARK: Override Theme

    @objc
    public enum NavigationBarStyle: Int {
        case clear, solid, alwaysDarkAndClear, alwaysDark, `default`
    }

    private var currentStyle: NavigationBarStyle?

    @objc
    public func switchToStyle(_ style: NavigationBarStyle, animated: Bool = false) {
        AssertIsOnMainThread()

        guard currentStyle != style else { return }

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

        switch style {
        case .clear:
            respectsTheme = false
            removeSecondaryAndSolidBarOverride()
            removeDarkThemeOverride()
            applyTransparentBarOverride()
        case .alwaysDarkAndClear:
            respectsTheme = false
            removeSecondaryAndSolidBarOverride()
            applyDarkThemeOverride()
            applyTransparentBarOverride()
        case .alwaysDark:
            respectsTheme = false
            removeSecondaryAndSolidBarOverride()
            removeTransparentBarOverride()
            applyDarkThemeOverride()
        case .default:
            respectsTheme = true
            removeDarkThemeOverride()
            removeTransparentBarOverride()
            removeSecondaryAndSolidBarOverride()
            applyTheme()
        case .solid:
            respectsTheme = true
            removeDarkThemeOverride()
            removeTransparentBarOverride()
            applySolidBarOverride()
            applyTheme()
        }
    }
}
