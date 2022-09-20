//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import SessionUIKit

@objc
public protocol NavBarLayoutDelegate: AnyObject {
    func navBarCallLayoutDidChange(navbar: OWSNavigationBar)
}

@objc
public class OWSNavigationBar: UINavigationBar {

    @objc
    public weak var navBarLayoutDelegate: NavBarLayoutDelegate?

    @objc
    public let navbarWithoutStatusHeight: CGFloat = 44

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

        themeBackgroundColor = .backgroundPrimary
        themeTintColor = .textPrimary
    }

    @objc
    public var respectsTheme: Bool = true {
        didSet {
            applyTheme()
        }
    }

    // MARK: Layout

    @objc
    public func didChangeStatusBarFrame() {
        Logger.debug("")
        self.navBarLayoutDelegate?.navBarCallLayoutDidChange(navbar: self)
    }
}
