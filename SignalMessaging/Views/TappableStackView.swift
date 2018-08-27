//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class TappableStackView: UIStackView {
    let actionBlock : (() -> Void)

    // MARK: - Initializers

    @available(*, unavailable, message: "use other constructor instead.")
    public required init(coder aDecoder: NSCoder) {
        notImplemented()
    }

    public required init(actionBlock : @escaping () -> Void) {
        self.actionBlock = actionBlock
        super.init(frame: CGRect.zero)

        self.isUserInteractionEnabled = true
        self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(wasTapped)))
    }

    @objc func wasTapped(sender: UIGestureRecognizer) {
        Logger.info("")

        guard sender.state == .recognized else {
            return
        }
        actionBlock()
    }
}
