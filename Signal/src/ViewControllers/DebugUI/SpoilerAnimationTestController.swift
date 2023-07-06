//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalUI

#if USE_DEBUG_UI

public class SpoilerAnimationTestController: UIViewController {

    private let animator = SpoilerAnimator()

    public override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .black

        let rowHeight: CGFloat = 40
        var totalHeight: CGFloat = 0
        while totalHeight < UIScreen.main.bounds.height {
            let view = UIImageView()
            view.tintColor = .white
            view.frame = CGRect(x: 0, y: totalHeight, width: UIScreen.main.bounds.width, height: rowHeight)
            totalHeight += rowHeight
            self.view.addSubview(view)
            animator.addObservingView(view)
        }
    }
}

#endif
