//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import UIKit

class AttachmentPrepContentView: UIView {

    let contentLayoutGuide = UILayoutGuide()
    private lazy var contentLayoutGuideLeading = contentLayoutGuide.leadingAnchor.constraint(equalTo: leadingAnchor, constant: contentLayoutMargins.leading)
    private lazy var contentLayoutGuideTop = contentLayoutGuide.topAnchor.constraint(equalTo: topAnchor, constant: contentLayoutMargins.top)
    private lazy var contentLayoutGuideTrailing = contentLayoutGuide.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -contentLayoutMargins.trailing)
    private lazy var contentLayoutGuideBottom = contentLayoutGuide.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -contentLayoutMargins.bottom)
    var contentLayoutMargins: UIEdgeInsets = .zero {
        didSet {
            contentLayoutGuideLeading.constant = contentLayoutMargins.leading
            contentLayoutGuideTop.constant = contentLayoutMargins.top
            contentLayoutGuideTrailing.constant = -contentLayoutMargins.trailing
            contentLayoutGuideBottom.constant = -contentLayoutMargins.bottom
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        addLayoutGuide(contentLayoutGuide)
        addConstraints([ contentLayoutGuideLeading, contentLayoutGuideTop, contentLayoutGuideTrailing, contentLayoutGuideBottom ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
