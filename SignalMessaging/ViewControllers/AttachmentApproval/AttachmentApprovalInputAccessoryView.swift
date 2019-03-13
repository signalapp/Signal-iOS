//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

class AttachmentApprovalInputAccessoryView: UIView {
    let attachmentTextToolbar: AttachmentTextToolbar
    let galleryRailView: GalleryRailView

    var isEditingMediaMessage: Bool {
        return attachmentTextToolbar.textView.isFirstResponder
    }

    let kGalleryRailViewHeight: CGFloat = 72

    required init(isAddMoreVisible: Bool) {
        attachmentTextToolbar = AttachmentTextToolbar(isAddMoreVisible: isAddMoreVisible)

        galleryRailView = GalleryRailView()
        galleryRailView.scrollFocusMode = .keepWithinBounds
        galleryRailView.autoSetDimension(.height, toSize: kGalleryRailViewHeight)

        super.init(frame: .zero)

        // Specifying auto-resizing mask and an intrinsic content size allows proper
        // sizing when used as an input accessory view.
        self.autoresizingMask = .flexibleHeight
        self.translatesAutoresizingMaskIntoConstraints = false

        backgroundColor = UIColor.black.withAlphaComponent(0.6)
        preservesSuperviewLayoutMargins = true

        let stackView = UIStackView(arrangedSubviews: [self.galleryRailView, self.attachmentTextToolbar])
        stackView.axis = .vertical

        addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: 

    override var intrinsicContentSize: CGSize {
        get {
            // Since we have `self.autoresizingMask = UIViewAutoresizingFlexibleHeight`, we must specify
            // an intrinsicContentSize. Specifying CGSize.zero causes the height to be determined by autolayout.
            return CGSize.zero
        }
    }
}
