//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

#if DEBUG
public class NavigationPreviewController: OWSNavigationController {
    private let animateFirstAppearance: Bool
    private let viewController: UIViewController

    public init(
        animateFirstAppearance: Bool = false,
        viewController: UIViewController,
    ) {
        self.animateFirstAppearance = animateFirstAppearance
        self.viewController = viewController
        super.init()
        // Need a root view controller to push over
        self.pushViewController(UIViewController(), animated: false)
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.pushViewController(self.viewController, animated: animateFirstAppearance)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#endif
