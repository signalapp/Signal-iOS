//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if USE_DEBUG_UI

import Foundation
import SignalUI
public import UIKit

final public class SpoilerAnimationTestController: UIViewController {

    private let spoilerAnimationManager = SpoilerAnimationManager()

    public override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .black

        let rowHeight: CGFloat = 40
        var totalHeight: CGFloat = 0
        while totalHeight < UIScreen.main.bounds.height {
            let view = TestSpoilerableView()
            view.tintColor = .white
            view.frame = CGRect(x: 0, y: totalHeight, width: UIScreen.main.bounds.width, height: rowHeight)
            totalHeight += rowHeight
            self.view.addSubview(view)
            spoilerAnimationManager.addViewAnimator(view)
        }
    }

    class TestSpoilerableView: UIView, SpoilerableViewAnimator {
        var spoilerableView: UIView? { self }

        var spoilerFramesCacheKey: Int { 0 }

        func spoilerFrames() -> [SpoilerFrame] {
            return [.init(frame: bounds, color: .fixed(tintColor), style: .standard)]
        }
    }
}

#endif
