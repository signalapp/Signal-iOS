//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public class OWSButton: UIButton {

    @objc
    var block: () -> Void = { }

    // MARK: -

    @objc
    init(block: @escaping () -> Void = { }) {
        super.init(frame: .zero)
        self.block = block
        self.addTarget(self, action: #selector(didTap), for: .touchUpInside)
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: -

    @objc
    func didTap() {
        block()
    }
}
