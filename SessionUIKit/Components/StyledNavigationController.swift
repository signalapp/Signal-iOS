// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit

public class StyledNavigationController: UINavigationController {
    public override var preferredStatusBarStyle: UIStatusBarStyle {
        return (
            self.topViewController?.preferredStatusBarStyle ??
            ThemeManager.currentTheme.statusBarStyle
        )
    }
}
