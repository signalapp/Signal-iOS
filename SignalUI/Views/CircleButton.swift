//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class CircleButton: OWSButton {

    // MARK: - Init

    @available(*, unavailable, message: "Use other constructor")
    required public init?(coder aDecoder: NSCoder) {
        fatalError("Use other constructor")
    }

    public override init(block: @escaping () -> Void) {
        super.init(block: block)

        configureConstraints()
    }

    private func configureConstraints() {
        autoPinToSquareAspectRatio()
    }

    // MARK: - Layout

    override public func layoutSubviews() {
        super.layoutSubviews()

        layer.cornerRadius = frame.size.width / 2
    }
}
