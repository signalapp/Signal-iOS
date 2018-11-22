//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

@objc
public protocol NavBarLayoutDelegate: class {
    func navBarCallLayoutDidChange(navbar: OWSNavigationBar)
}

@objc
public class OWSNavigationBar: UINavigationBar {

    @objc
    public weak var navBarLayoutDelegate: NavBarLayoutDelegate?

    @objc
    public let navbarWithoutStatusHeight: CGFloat = 44

    @objc
    public var callBannerHeight: CGFloat {
        return OWSWindowManagerCallBannerHeight()
    }

    @objc
    public var statusBarHeight: CGFloat {
        return CurrentAppContext().statusBarHeight
    }

    @objc
    public var fullWidth: CGFloat {
        return UIScreen.main.bounds.size.width
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

        NotificationCenter.default.addObserver(self, selector: #selector(callDidChange), name: .OWSWindowManagerCallDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didChangeStatusBarFrame), name: .UIApplicationDidChangeStatusBarFrame, object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(themeDidChange),
                                               name: .ThemeDidChange,
                                               object: nil)
    }

    // MARK: Theme

    private func applyTheme() {
        guard respectsTheme else {
            removeBlurEffectView()

            self.setBackgroundImage(nil, for: .default)
            return
        }

        if UIAccessibilityIsReduceTransparencyEnabled() {
            removeBlurEffectView()
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

    // MARK: Layout

    @objc
    public func callDidChange() {
        Logger.debug("")
        self.navBarLayoutDelegate?.navBarCallLayoutDidChange(navbar: self)
    }

    @objc
    public func didChangeStatusBarFrame() {
        Logger.debug("")
        self.navBarLayoutDelegate?.navBarCallLayoutDidChange(navbar: self)
    }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard OWSWindowManager.shared().hasCall() else {
            return super.sizeThatFits(size)
        }

        if #available(iOS 11, *) {
            return super.sizeThatFits(size)
        } else if #available(iOS 10, *) {
            // iOS10
            // sizeThatFits is repeatedly called to determine how much space to reserve for that navbar.
            // That is, increasing this causes the child view controller to be pushed down.
            // (as of iOS11, this is not used and instead we use additionalSafeAreaInsets)
            return CGSize(width: fullWidth, height: navbarWithoutStatusHeight + statusBarHeight)
        } else {
            // iOS9
            // sizeThatFits is repeatedly called to determine how much space to reserve for that navbar.
            // That is, increasing this causes the child view controller to be pushed down.
            // (as of iOS11, this is not used and instead we use additionalSafeAreaInsets)            
            return CGSize(width: fullWidth, height: navbarWithoutStatusHeight + callBannerHeight + 20)
        }
    }

    public override func layoutSubviews() {
        guard OWSWindowManager.shared().hasCall() else {
            super.layoutSubviews()
            return
        }

        guard #available(iOS 11, *) else {
            super.layoutSubviews()
            return
        }

        self.frame = CGRect(x: 0, y: callBannerHeight, width: fullWidth, height: navbarWithoutStatusHeight)
        self.bounds = CGRect(x: 0, y: 0, width: fullWidth, height: navbarWithoutStatusHeight)

        super.layoutSubviews()

        // This is only necessary on iOS11, which has some private views within that lay outside of the navbar.
        // They aren't actually visible behind the call status bar, but they looks strange during present/dismiss
        // animations for modal VC's
        for subview in self.subviews {
            let stringFromClass = NSStringFromClass(subview.classForCoder)
            if stringFromClass.contains("BarBackground") {
                subview.frame = self.bounds
            } else if stringFromClass.contains("BarContentView") {
                subview.frame = self.bounds
            }
        }
    }

    // MARK: 

    @objc
    public func makeClear() {
        self.backgroundColor = .clear
        // Making a toolbar transparent requires setting an empty uiimage
        self.setBackgroundImage(UIImage(), for: .default)
        self.shadowImage = UIImage()
        self.clipsToBounds = true
        removeBlurEffectView()
    }

    // MARK:

    private func removeBlurEffectView() {
        // Avoid crash on iOS 10.3.3 and iOS 9.4.
        //
        // Last Exception Backtrace:
        // 0   CoreFoundation                    0x1b6bfb38 __exceptionPreprocess + 124 (NSException.m:165)
        // 1   libobjc.A.dylib                   0x1a947062 objc_exception_throw + 34 (objc-exception.mm:521)
        // 2   CoreFoundation                    0x1b6bfa80 +[NSException raise:format:] + 104 (NSException.m:140)
        // 3   UIKit                             0x20bfc9fe -[UINavigationBar removeConstraint:] + 84 (UINavigationBar.m:4618)
        // 4   UIKit                             0x208ee3d4 _UIViewRemoveConstraintsMadeDanglyByChangingSuperview + 534 // (NSLayoutConstraint_UIKitAdditions.m:4716)
        // 5   UIKit                             0x208ede90 __45-[UIView(Hierarchy) _postMovedFromSuperview:]_block_invoke + 40 // (UIView.m:9467)
        // 6   UIKit                             0x208edd6c -[UIView(Hierarchy) _postMovedFromSuperview:] + 710 (UIView.m:361)
        // 7   UIKit                             0x20bd19e8 __UIViewWasRemovedFromSuperview + 154 (UIView.m:8889)
        // 8   UIKit                             0x208ecf6a -[UIView(Hierarchy) removeFromSuperview] + 528 (UIView.m:8961)
        // 9   SignalMessaging                   0x1d42b64 OWSNavigationBar.applyTheme() + 218 (OWSNavigationBar.swift:62)
        if #available(iOS 11, *) {
            self.blurEffectView?.removeFromSuperview()
        } else {
            self.blurEffectView?.isHidden = true
        }
    }
}
