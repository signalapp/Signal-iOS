//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

@objc
class SignalNavigationBar: UINavigationBar {

    // TODO - get a more precise value
    // TODO - test with other heights, e.g. w/ hotspot, w/ call in other app
    let navbarHeight: CGFloat = 44

    override init(frame: CGRect) {
        super.init(frame: frame)

        // TODO better place to observe?
        NotificationCenter.default.addObserver(forName: .OWSWindowManagerCallDidChange, object: nil, queue: nil) { _ in
            Logger.debug("\(self.logTag) in \(#function) OWSWindowManagerCallDidChange")

            self.callDidChange()
        }
    }

    private func callDidChange() {
        if #available(iOS 11, *) {
            self.layoutSubviews()
        } else {
            self.sizeToFit()
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        // pre iOS11, sizeThatFits is repeatedly called to size the navbar, which is pretty straight forward
        // as of iOS11, this is not true and we have to do things in layoutSubviews.
        // FIXME: pre-iOS11, though the size is right, there's a glitch on the titleView while push/popping items.
        let result: CGSize = {
            if OWSWindowManager.shared().hasCall() {
                // status bar height gets re-added
                return CGSize(width: UIScreen.main.bounds.width, height: navbarHeight - UIApplication.shared.statusBarFrame.size.height)
            } else {
                return super.sizeThatFits(size)
            }
        }()

        Logger.debug("\(self.logTag) in \(#function): \(result)")

        return result
    }

    // seems unused.
//    override var intrinsicContentSize: CGSize {
//        return CGSize(width: UIScreen.main.bounds.width, height: navbarHeight)
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

        guard #available(iOS 11.0, *), OWSWindowManager.shared().hasCall() else {
            super.layoutSubviews()
            return
        }

//        let rect = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: self.navbarHeightWithoutStatusBar)
//        self.frame = CGRect(x: 0, y: 20, width: UI Screen.main.bounds.width, height: ios11NavbarHeight)
        self.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: navbarHeight)
        self.bounds = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: navbarHeight)

        super.layoutSubviews()

        for subview in self.subviews {
            let stringFromClass = NSStringFromClass(subview.classForCoder)
            if stringFromClass.contains("BarBackground") {
                subview.frame = self.bounds
            } else if stringFromClass.contains("BarContentView") {
                subview.frame = self.bounds
            }
        }
    }
}
