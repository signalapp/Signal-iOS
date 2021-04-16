//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class CVLabel: UILabel {
    public override func updateConstraints() {
        super.updateConstraints()

        deactivateAllConstraints()
    }
}

// MARK: -

@objc
public class CVImageView: UIImageView {
    public override func updateConstraints() {
        super.updateConstraints()

        deactivateAllConstraints()
    }
}

// MARK: -

@objc
public class CVAnimatedImageView: YYAnimatedImageView {
    public override func updateConstraints() {
        super.updateConstraints()

        deactivateAllConstraints()
    }
}
