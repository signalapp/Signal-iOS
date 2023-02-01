//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

public protocol CustomBackgroundColorCell {
    func customBackgroundColor(forceDarkMode: Bool) -> UIColor
    func customSelectedBackgroundColor(forceDarkMode: Bool) -> UIColor
}
