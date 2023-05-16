//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit

@objc
public enum OWSNavigationBarStyle: Int {
    case solid, alwaysDark, blur

    var forcedStatusBarStyle: UIStatusBarStyle? {
        switch self {
        case .solid:
            return nil
        case .alwaysDark:
            return .lightContent
        case .blur:
            return nil
        }
    }
}

public class OWSNavigationBar: UINavigationBar {

    public var fullWidth: CGFloat {
        return superview?.frame.width ?? .zero
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// This is the alpha we apply to UIVisualEffectView colors to achieve the blur effect we want.
    public static let backgroundBlurMutingFactor: CGFloat = 0.5

    /// This is the reference to the UIVisualEffectView we create ourselves on iOS 14 and earlier.
    /// We own the layout and properties of this view.
    private var manualBlurEffectView: UIVisualEffectView?

    /// This is a reference to the UIVisualEffectView UIKit creates from UINavigationBarAppearance.
    /// We find it by walking through the view hierarchy. We do not lay this view out, but we
    /// need to modify its properties to get the blur effect we want.
    private var appearanceBlurEffectView: UIVisualEffectView? {
        didSet {
            appearanceBlurEffectViewSublayerObservation?.invalidate()
            appearanceBlurEffectViewSublayerObservation = nil
            appearanceBlurEffectViewBackgroundColorObservation?.invalidate()
            appearanceBlurEffectViewBackgroundColorObservation = nil
        }
    }
    /// These are KVO observations we keep on the nodes in the view heirarchy graph so
    /// we can keep our `appearanceBlurEffectView` reference up to date.
    private var backgroundSublayerObservation: NSKeyValueObservation?
    private var appearanceBlurEffectViewSublayerObservation: NSKeyValueObservation?
    private var appearanceBlurEffectViewBackgroundColorObservation: NSKeyValueObservation?

    override init(frame: CGRect) {
        super.init(frame: frame)

        updateAppearance(animated: false)
    }

    public override func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)

        if #available(iOS 15, *) {
            if String(describing: type(of: subview)) == "_UIBarBackground" {
                // The background gets created before the UIVisualEffectView that gets added
                // as a subview of it, not of the root. This gives us a hook to know
                // when the UIVisualEffectView gets added.
                backgroundSublayerObservation?.invalidate()
                backgroundSublayerObservation = subview.layer.observe(\.sublayers) { [weak self] _, _ in
                    self?.setAppearanceBlurViewIfExists()
                }
            }

            setAppearanceBlurViewIfExists()
        }
    }

    public override var barPosition: UIBarPosition {
        return .topAttached
    }

    public var forcedStatusBarStyle: UIStatusBarStyle? {
        return style?.forcedStatusBarStyle
    }

    // MARK: Background Color

    internal var navbarBackgroundColorOverride: UIColor?

    private var navbarBackgroundColor: UIColor {
        return navbarBackgroundColorOverride ?? Theme.navbarBackgroundColor
    }

    // MARK: Appearance

    private var style: OWSNavigationBarStyle?
    private var appearance: OWSNavigationBarAppearance?

    internal func setStyle(_ style: OWSNavigationBarStyle, animated: Bool) {
        self.style = style
        updateAppearance(animated: animated)
    }

    private func updateAppearance(animated: Bool) {
        AssertIsOnMainThread()

        let appearance = OWSNavigationBarAppearance.appearance(
            for: style ?? .blur,
            navbarBackgroundColor: navbarBackgroundColor
        )

        guard appearance != self.appearance else {
            return
        }

        if animated {
            let animation = CATransition()
            animation.duration = 0.35
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.type = .fade
            layer.add(animation, forKey: "ows_fade")
        } else {
            layer.removeAnimation(forKey: "ows_fade")
        }

        appearance.apply(to: self)
        self.appearance = appearance
    }

    // MARK: - iOS >15 blur hacks

    @available(iOS 15, *)
    fileprivate func setAppearanceBlurViewIfExists() {
        var subviews: [UIView] = [self]
        while let subview = subviews.popLast() {
            if let blurView = subview as? UIVisualEffectView {
                self.appearanceBlurEffectView = blurView
                self.updateAppearanceBlurView()
                break
            }
            subviews.append(contentsOf: subview.subviews)
        }
    }

    @available(iOS 15, *)
    fileprivate func updateAppearanceBlurView() {
        guard let appearanceBlurEffectView else {
            appearanceBlurEffectView = nil
            return
        }
        guard let tintingView = appearanceBlurEffectView.tintingView else {
            appearanceBlurEffectViewBackgroundColorObservation?.invalidate()
            appearanceBlurEffectViewBackgroundColorObservation = nil
            if appearanceBlurEffectViewSublayerObservation == nil {
                // The blur view gets created without its subviews at first, but its those
                // subviews we need to adjust. This gives us a hook to know when they get added.
                appearanceBlurEffectViewSublayerObservation?.invalidate()
                appearanceBlurEffectViewSublayerObservation = appearanceBlurEffectView.layer.observe(\.sublayers) { [weak self] _, _ in
                    self?.updateAppearanceBlurView()
                }
            }
            return
        }
        appearanceBlurEffectViewBackgroundColorObservation?.invalidate()
        appearanceBlurEffectViewBackgroundColorObservation = nil
        let desiredBgColor = navbarBackgroundColor.withAlphaComponent(Self.backgroundBlurMutingFactor)
        appearanceBlurEffectViewSublayerObservation?.invalidate()
        appearanceBlurEffectViewSublayerObservation = nil
        appearanceBlurEffectView.matchBackgroundColor(desiredBgColor)
        appearanceBlurEffectViewBackgroundColorObservation = tintingView.observe(\.backgroundColor, changeHandler: { [weak self] view, _ in
            if view.backgroundColor != desiredBgColor {
                self?.updateAppearanceBlurView()
            }
        })
    }

    // MARK: - iOS <=14 blur hacks

    fileprivate func updateBlurView(_ effect: UIVisualEffect?) {
        if #available(iOS 15, *) {
            owsFailDebug("Shouldn't use a UIVisualEffectView on iOS 15+, use appearance instead")
            return
        }
        guard let effect else {
            manualBlurEffectView?.isHidden = true
            return
        }
        let blurEffectView: UIVisualEffectView = {
            if let existingBlurEffectView = self.manualBlurEffectView {
                existingBlurEffectView.removeFromSuperview()
                self.manualBlurEffectView = nil
            }

            let blurEffectView = UIVisualEffectView()
            blurEffectView.isUserInteractionEnabled = false

            self.manualBlurEffectView = blurEffectView
            self.insertSubview(blurEffectView, at: 0)

            // navbar frame doesn't account for statusBar, so, same as the built-in navbar background, we need to exceed
            // the navbar bounds to have the blur extend up and behind the status bar.
            let statusBarHeight = CurrentAppContext().statusBarHeight
            blurEffectView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: -statusBarHeight, left: 0, bottom: 0, right: 0))

            return blurEffectView
        }()

        blurEffectView.effect = effect

        // remove hairline below bar.
        self.shadowImage = UIImage()

        // On iOS11, despite inserting the blur at 0, other views are later inserted into the navbar behind the blur,
        // so we have to set a zindex to avoid obscuring navbar title/buttons.
        blurEffectView.layer.zPosition = -1

        let bgColor = navbarBackgroundColor.withAlphaComponent(OWSNavigationBar.backgroundBlurMutingFactor)
        if !blurEffectView.matchBackgroundColor(bgColor) {
            // If we can't find the tinting subview (e.g. a new iOS version changed the behavior)
            // We'll make the navbar more translucent by setting a background color.
            let color = navbarBackgroundColor.withAlphaComponent(OWSNavigationBar.backgroundBlurMutingFactor)
            let backgroundImage = UIImage(color: color)
            self.setBackgroundImage(backgroundImage, for: .default)
        }
    }
}

internal struct OWSNavigationBarAppearance: Equatable {

    var tintColor: UIColor?
    var barStyle: UIBarStyle = .default

    var isTranslucent: Bool = false
    var clipsToBounds: Bool = false

    enum BackgroundStyle: Equatable {
        case blur(UIBlurEffect)
        case tint(UIColor)
        case image(UIColor)
    }

    var backgroundStyle: BackgroundStyle = .blur(UIBlurEffect(style: .regular))

    var hasShadowImage: Bool = false

    var titleTextColor: UIColor?

    static func appearance(for style: OWSNavigationBarStyle, navbarBackgroundColor: UIColor) -> Self {
        var appearance = OWSNavigationBarAppearance()
        appearance.barStyle = Theme.barStyle
        appearance.tintColor = Theme.primaryTextColor
        if UIAccessibility.isReduceTransparencyEnabled {
            appearance.backgroundStyle = .image(navbarBackgroundColor)
        } else {
            appearance.backgroundStyle = .blur(Theme.barBlurEffect)
        }
        appearance.titleTextColor = Theme.primaryTextColor
        appearance.clipsToBounds = false
        appearance.hasShadowImage = false
        appearance.isTranslucent = false

        let applyTranslucency = {
            appearance.isTranslucent = !UIAccessibility.isReduceTransparencyEnabled
        }

        let applyDarkThemeOverride = {
            appearance.barStyle = .black
            appearance.backgroundStyle = .tint(Theme.darkThemeBackgroundColor)
            appearance.tintColor = Theme.darkThemePrimaryColor
        }

        let applySolidBarOverride = {
            appearance.backgroundStyle = .image(navbarBackgroundColor)
            appearance.hasShadowImage = true
        }

        switch style {
        case .alwaysDark:
            applyDarkThemeOverride()
            applyTranslucency()
        case .blur:
            applyTranslucency()
        case .solid:
            applySolidBarOverride()
            applyTranslucency()
        }

        return appearance
    }

    func apply(to navigationBar: OWSNavigationBar) {
        if #available(iOS 15, *) {
            applyForiOS15(to: navigationBar)
        } else {
            applyForiOS13(to: navigationBar)
        }

        // Apply the common properties
        navigationBar.isTranslucent = isTranslucent
        navigationBar.clipsToBounds = clipsToBounds
        navigationBar.barStyle = barStyle
        navigationBar.tintColor = tintColor
        navigationBar.barTintColor = backgroundColor
    }

    // We use appearance APIs on iOS 15+. They only exist in iOS 13+,
    // but are buggy on iOS 13 and 14, so we only use them on iOS 15+.
    @available(iOS 15, *)
    private func applyForiOS15(to navigationBar: OWSNavigationBar) {
        let appearance = UINavigationBarAppearance()
        appearance.backgroundEffect = blurEffect
        appearance.backgroundColor = backgroundColor
        appearance.backgroundImage = backgroundImage
        appearance.titleTextAttributes = titleTextAttributes
        appearance.shadowImage = shadowImage
        // We have to override the color default, we never use it.
        appearance.shadowColor = nil

        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.compactScrollEdgeAppearance = appearance

        // navigationBar.setAppearanceBlurViewIfExists()
        navigationBar.updateAppearanceBlurView()
    }

    // On iOS 14 and earlier we don't use appearance APIs and instead
    // set our own UIVisualEffectView.
    private func applyForiOS13(to navigationBar: OWSNavigationBar) {
        navigationBar.backgroundColor = backgroundColor
        navigationBar.setBackgroundImage(backgroundImage, for: .default)
        navigationBar.titleTextAttributes = titleTextAttributes
        navigationBar.shadowImage = shadowImage
        navigationBar.updateBlurView(blurEffect)
    }

    private var backgroundImage: UIImage? {
        switch backgroundStyle {
        case .blur:
            return UIImage(color: .clear)
        case .tint:
            return nil
        case .image(let color):
            return UIImage(color: color)
        }
    }

    private var blurEffect: UIBlurEffect? {
        switch backgroundStyle {
        case .tint, .image:
            return nil
        case .blur(let effect):
            return effect
        }
    }

    private var backgroundColor: UIColor? {
        switch backgroundStyle {
        case .blur, .image:
            return nil
        case .tint(let color):
            return color
        }
    }

    private var shadowImage: UIImage? {
        return hasShadowImage ? UIImage() : nil
    }

    private var titleTextAttributes: [NSAttributedString.Key: Any] {
        var attributes = [NSAttributedString.Key: Any]()
        if let titleTextColor = titleTextColor {
            attributes[.foregroundColor] = titleTextColor
        }
        return attributes
    }
}

fileprivate extension UIVisualEffectView {

    var tintingView: UIView? {
        return subviews.first(where: {
            String(describing: type(of: $0)) == "_UIVisualEffectSubview"
        })
    }

    /// Alter the visual effect view's tint to match a background color
    /// so the navbar, when over a solid color background matching navbarBackgroundColor,
    /// exactly matches the background color. This is brittle, but there is no way to get
    /// this behavior from UIVisualEffectView otherwise.
    /// Return true if this was successful, and false otherwise.
    @discardableResult
    func matchBackgroundColor(_ color: UIColor) -> Bool {
        if let tintingView = tintingView {
            tintingView.backgroundColor = color
            return true
        } else {
            owsFailDebug("Unexpectedly missing visual effect subview")
            return false
        }
    }
}
