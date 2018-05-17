//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

@objc
class OWSNavigationBar: UINavigationBar {

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
        Logger.debug("\(self.logTag) in \(#function) OWSWindowManagerCallDidChange")

        if #available(iOS 11, *) {
            self.layoutSubviews()
        } else {
            self.sizeToFit()
            self.frame.origin.y = statusBarHeight

            self.layoutSubviews()
        }
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
            // pre iOS11, sizeThatFits is repeatedly called to size the navbar
            // as of iOS11, this is not true and we have to size things in layoutSubviews.
            // FIXME: pre-iOS11, though the size is right, there's a glitch on the titleView while push/popping items.
            let result = CGSize(width: CurrentAppContext().mainWindow!.bounds.width, height: navbarWithoutStatusHeight + statusBarHeight)

            Logger.debug("\(self.logTag) in \(#function): \(result)")

            return result
        }
    }

//    override var center: CGPoint {
//        get {
//            Logger.debug("\(self.logTag) in \(#function)")
//            return super.center
//        }
//        set {
//            Logger.debug("\(self.logTag) in \(#function)")
//            if OWSWindowManager.shared().hasCall() {
//                var translated = newValue
////                translated.y -= 20
//                super.center = translated
//            } else {
//                super.center = newValue
//            }
//        }
//    }

    // seems unused.
//    override var intrinsicContentSize: CGSize {
//        return CGSize(width: UIScreen.main.bounds.width, height: navbarWithoutStatusHeight)
//        return CGSize(width: UIScreen.main.bounds.width, height: 20)
//    }

//    override var bounds: CGRect {
//        get {
//            return super.bounds
//        }
//        set {
//            super.bounds = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: ios11NavbarHeight)
//        }
//    }
//
//    override var frame: CGRect {
//        get {
//            return super.frame
//        }
//        set {
//            super.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: ios11NavbarHeight)
//        }
//    }

    override func layoutSubviews() {
        Logger.debug("\(self.logTag) in \(#function)")

        guard OWSWindowManager.shared().hasCall() else {
//        guard #available(iOS 11.0, *), OWSWindowManager.shared().hasCall() else {
            super.layoutSubviews()
            return
        }

//        let rect = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: self.navbarHeightWithoutStatusBar)
//        self.frame = CGRect(x: 0, y: 20, width: UI Screen.main.bounds.width, height: ios11NavbarHeight)
        self.frame = CGRect(x: 0, y: callBannerHeight, width: UIScreen.main.bounds.width, height: navbarWithoutStatusHeight)
        self.bounds = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: navbarWithoutStatusHeight)

        super.layoutSubviews()

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
