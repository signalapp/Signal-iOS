//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class TappableView: UIView {
    let actionBlock: (() -> Void)

    // MARK: - Initializers

    @available(*, unavailable, message: "use other constructor instead.")
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public required init(actionBlock: @escaping () -> Void) {
        self.actionBlock = actionBlock
        super.init(frame: CGRect.zero)

        self.isUserInteractionEnabled = true
        self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(wasTapped)))
    }

    @objc
    func wasTapped(sender: UIGestureRecognizer) {
        Logger.info("")

        guard sender.state == .recognized else {
            return
        }
        actionBlock()
    }
}
