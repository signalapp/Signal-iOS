//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import UIKit

/// Holds an "unlocked lock" icon displayed for SMS messages.
///
/// - Note
/// SMS messages have never been supported on iOS, but might theoretically be
/// restored to an iOS device from a Backup created on an Android device that
/// had SMS messages.
final class SmsLockIconView: ManualLayoutView {
    private let imageView: UIImageView

    static let size: CGSize = .square(12)

    init() {
        imageView = UIImageView(image: UIImage(named: "unlocked-lock")!)

        super.init(name: "SmsLockIconView")
        addSubviewToFillSuperviewEdges(imageView)
    }

    func configure(tintColor: UIColor) {
        imageView.tintColor = tintColor
    }
}
