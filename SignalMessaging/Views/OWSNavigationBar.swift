//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

@objc
protocol NavBarLayoutDelegate: class {
    func navBarCallLayoutDidChange(navbar: OWSNavigationBar)
}

@objc
class OWSNavigationBar: UINavigationBar {

    weak var navBarLayoutDelegate: NavBarLayoutDelegate?

    // TODO - get a more precise value
    // TODO - test with other heights, e.g. w/ hotspot, w/ call in other app
    let navbarWithoutStatusHeight: CGFloat = 44
    let callBannerHeight: CGFloat = 40

    // MJK safe to hardcode? Do we even need this approach anymore?
    var statusBarHeight: CGFloat {
        // TODO? plumb through CurrentAppContext()
        return 20
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.isTranslucent = false

        NotificationCenter.default.addObserver(self, selector: #selector(callDidChange), name: .OWSWindowManagerCallDidChange, object: nil)
    }

    @objc
    public func callDidChange() {
        Logger.debug("\(self.logTag) in \(#function)")
        self.navBarLayoutDelegate?.navBarCallLayoutDidChange(navbar: self)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard OWSWindowManager.shared().hasCall() else {
            return super.sizeThatFits(size)
        }

        if #available(iOS 11, *) {
            return super.sizeThatFits(size)
        } else {
            // pre iOS11, sizeThatFits is repeatedly called to determine how much space to reserve for that navbar.
            // That is, increasing this causes the child view controller to be pushed down.
            // (as of iOS11, this is not used and instead we use additionalSafeAreaInsets)
            let result = CGSize(width: CurrentAppContext().mainWindow!.bounds.width, height: navbarWithoutStatusHeight + statusBarHeight)

            Logger.debug("\(self.logTag) in \(#function): \(result)")

            return result
        }
    }

    override func layoutSubviews() {
        Logger.debug("\(self.logTag) in \(#function)")

        guard OWSWindowManager.shared().hasCall() else {
            super.layoutSubviews()
            return
        }

//        let rect = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: self.navbarHeightWithoutStatusBar)
//        self.frame = CGRect(x: 0, y: 20, width: UI Screen.main.bounds.width, height: ios11NavbarHeight)
        self.frame = CGRect(x: 0, y: callBannerHeight, width: UIScreen.main.bounds.width, height: navbarWithoutStatusHeight)
        self.bounds = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: navbarWithoutStatusHeight)

        super.layoutSubviews()

        guard #available(iOS 11, *) else {
            return
        }

        // This is only necessary on iOS11, which has some private views within the navbar
        for subview in self.subviews {
            let stringFromClass = NSStringFromClass(subview.classForCoder)
            if stringFromClass.contains("BarBackground") {
                subview.frame = self.bounds//.offsetBy(dx: 0, dy: 20)
            } else if stringFromClass.contains("BarContentView") {
                subview.frame = self.bounds//.offsetBy(dx: 0, dy: 20)
            }
        }
    }
}
