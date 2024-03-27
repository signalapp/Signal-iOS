//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit

public struct ThemedColor: Equatable, Hashable {
    private let light: UIColor
    private let dark: UIColor

    public init(light: UIColor, dark: UIColor) {
        self.light = light
        self.dark = dark
    }

    public func color(isDarkThemeEnabled: Bool) -> UIColor {
        return isDarkThemeEnabled ? dark : light
    }
}
