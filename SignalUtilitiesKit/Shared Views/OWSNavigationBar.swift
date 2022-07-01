//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import SessionUIKit

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
        NotificationCenter.default.addObserver(self, selector: #selector(didChangeStatusBarFrame), name: UIApplication.didChangeStatusBarFrameNotification, object: nil)
    }

    // MARK: FirstResponder Stubbing

    @objc
    public weak var stubbedNextResponder: UIResponder?

    override public var next: UIResponder? {
        if let stubbedNextResponder = self.stubbedNextResponder {
            return stubbedNextResponder
        }

        return super.next
    }

    // MARK: Theme

    private func applyTheme() {
        guard respectsTheme else {
            return
        }

        backgroundColor = Colors.navigationBarBackground
        
        tintColor = Colors.text
        
        if UIAccessibility.isReduceTransparencyEnabled {
            blurEffectView?.isHidden = true
            let color = UIColor.lokiDarkestGray()
            let backgroundImage = UIImage(color: color)
            self.setBackgroundImage(backgroundImage, for: .default)
        } else {
            // Make navbar more translucent than default. Navbars remove alpha from any assigned backgroundColor, so
            // to achieve transparency, we have to assign a transparent image.
            let color = UIColor.lokiDarkestGray()
            let backgroundImage = UIImage(color: color)
            self.setBackgroundImage(backgroundImage, for: .default)

            // remove hairline below bar.
            self.shadowImage = UIImage()
        }
    }

    @objc
    public var respectsTheme: Bool = true {
        didSet {
            applyTheme()
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

    public override func layoutSubviews() {
        guard CurrentAppContext().isMainApp else {
            super.layoutSubviews()
            return
        }
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

    // MARK: Override Theme

    @objc
    public enum NavigationBarThemeOverride: Int {
        case clear, alwaysDark
    }

    @objc
    public func overrideTheme(type: NavigationBarThemeOverride) {
        respectsTheme = false

        barStyle = .black
        titleTextAttributes = [NSAttributedString.Key.foregroundColor: Colors.text]
        barTintColor = Colors.navigationBarBackground.withAlphaComponent(0.6)
        tintColor = Colors.text

        switch type {
        case .clear:
            blurEffectView?.isHidden = true
            clipsToBounds = true

            // Making a toolbar transparent requires setting an empty uiimage
            setBackgroundImage(UIImage(), for: .default)
            shadowImage = UIImage()
            backgroundColor = .clear
        case .alwaysDark:
            blurEffectView?.isHidden = false
            clipsToBounds = false

            setBackgroundImage(nil, for: .default)
            shadowImage = nil
        }
    }
}
