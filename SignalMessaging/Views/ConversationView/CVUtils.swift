//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import YYImage

public class CVUtils {

    @available(*, unavailable, message: "use other init() instead.")
    private init() {}

    public static let workQueue: DispatchQueue = {
        // Note that we use the highest qos.
        DispatchQueue(label: "org.whispersystems.signal.conversationView",
                             qos: .userInteractive,
                             autoreleaseFrequency: .workItem)
    }()
}

// MARK: -

@objc
open class CVLabel: UILabel {
    public override func updateConstraints() {
        super.updateConstraints()

        deactivateAllConstraints()
    }
}

// MARK: -

@objc
open class CVImageView: UIImageView {
    public override func updateConstraints() {
        super.updateConstraints()

        deactivateAllConstraints()
    }
}

// MARK: -

@objc
open class CVAnimatedImageView: YYAnimatedImageView {
    public override func updateConstraints() {
        super.updateConstraints()

        deactivateAllConstraints()
    }
}
