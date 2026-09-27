//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if USE_DEBUG_UI

import Foundation
import SignalUI
public import UIKit

public class SpoilerAnimationTestController: UIViewController {

    private let spoilerAnimationManager = SpoilerAnimationManager()

    override public func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        view.removeAllSubviews()

        guard let window = view.window else { return }

        let windowSize = window.bounds.size
        let rowHeight: CGFloat = 40
        var totalHeight: CGFloat = 0
        while totalHeight < windowSize.height {
            let spoilerView = TestSpoilerableView()
            spoilerView.tintColor = .white
            spoilerView.frame = CGRect(x: 0, y: totalHeight, width: windowSize.width, height: rowHeight)
            totalHeight += rowHeight
            view.addSubview(spoilerView)
            spoilerAnimationManager.addViewAnimator(spoilerView)
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
