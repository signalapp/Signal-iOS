//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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
        notImplemented()
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

    private func applyTheme() {
        guard respectsTheme else {
            return
        }

        if currentStyle == .secondaryBar {
            let color = Theme.secondaryBackgroundColor
            let backgroundImage = UIImage(color: color)
            self.setBackgroundImage(backgroundImage, for: .default)
        } else if UIAccessibility.isReduceTransparencyEnabled {
            blurEffectView?.isHidden = true
            let color = Theme.navbarBackgroundColor
            let backgroundImage = UIImage(color: color)
            self.setBackgroundImage(backgroundImage, for: .default)
        } else {
            // Make navbar more translucent than default. Navbars remove alpha from any assigned backgroundColor, so
            // to achieve transparency, we have to assign a transparent image.
            let color = Theme.navbarBackgroundColor.withAlphaComponent(OWSNavigationBar.backgroundBlurMutingFactor)
            let backgroundImage = UIImage(color: color)
            self.setBackgroundImage(backgroundImage, for: .default)

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
        case clear, alwaysDark, `default`, secondaryBar
    }

    private var currentStyle: NavigationBarStyle?

    @objc
    public func switchToStyle(_ style: NavigationBarStyle) {
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

        let applySecondaryBarOverride = {
            self.blurEffectView?.isHidden = true
            self.shadowImage = UIImage()
        }

        let removeSecondaryBarOverride = {
            self.blurEffectView?.isHidden = false
            self.shadowImage = nil
        }

        currentStyle = style

        switch style {
        case .clear:
            respectsTheme = false
            removeSecondaryBarOverride()
            applyDarkThemeOverride()
            applyTransparentBarOverride()
        case .alwaysDark:
            respectsTheme = false
            removeSecondaryBarOverride()
            removeTransparentBarOverride()
            applyDarkThemeOverride()
        case .default:
            respectsTheme = true
            removeDarkThemeOverride()
            removeTransparentBarOverride()
            removeSecondaryBarOverride()
            applyTheme()
        case .secondaryBar:
            respectsTheme = true
            removeDarkThemeOverride()
            removeTransparentBarOverride()
            applySecondaryBarOverride()
            applyTheme()
        }
    }
}
