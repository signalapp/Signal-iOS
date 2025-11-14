//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import UIKit

final class PinnedMessageIconView: ManualLayoutView {
    private let imageView = CVImageView()
    static let size: CGSize = .square(12)

    init() {
        super.init(name: "PinnedMessageIconView")

        addSubviewToFillSuperviewEdges(imageView)
    }

    func configure(tintColor: UIColor) {
        imageView.image = .pinFill
        imageView.tintColor = tintColor
    }
}
