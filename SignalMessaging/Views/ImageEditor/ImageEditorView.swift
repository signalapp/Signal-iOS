//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public class ImageEditorView: UIView {
    private let model: ImageEditorModel

    @objc
    public required init(model: ImageEditorModel) {
        self.model = model

        super.init(frame: .zero)
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }
}
