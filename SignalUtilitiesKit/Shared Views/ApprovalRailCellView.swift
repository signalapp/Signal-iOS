// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit

protocol ApprovalRailCellViewDelegate: AnyObject {
    func approvalRailCellView(_ approvalRailCellView: ApprovalRailCellView, didRemoveItem attachmentItem: SignalAttachmentItem)
    func canRemoveApprovalRailCellView(_ approvalRailCellView: ApprovalRailCellView) -> Bool
}

// MARK: -

public class ApprovalRailCellView: GalleryRailCellView {

    weak var approvalRailCellDelegate: ApprovalRailCellViewDelegate?

    lazy var deleteButton: UIButton = {
        let button = OWSButton { [weak self] in
            guard let strongSelf = self else { return }

            guard let attachmentItem = strongSelf.item as? SignalAttachmentItem else {
                owsFailDebug("attachmentItem was unexpectedly nil")
                return
            }

            strongSelf.approvalRailCellDelegate?.approvalRailCellView(strongSelf, didRemoveItem: attachmentItem)
        }

        button.setImage(UIImage(named: "x-24")?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.themeTintColor = .white
        button.themeShadowColor = .black
        button.layer.shadowRadius = 2
        button.layer.shadowOpacity = 0.66
        button.layer.shadowOffset = .zero

        let kButtonWidth: CGFloat = 24
        button.autoSetDimensions(to: CGSize(width: kButtonWidth, height: kButtonWidth))

        return button
    }()

    lazy var captionIndicator: UIView = {
        let image = UIImage(named: "image_editor_caption")?.withRenderingMode(.alwaysTemplate)
        let imageView = UIImageView(image: image)
        imageView.themeTintColor = .white
        imageView.themeShadowColor = .black
        imageView.layer.shadowRadius = 2
        imageView.layer.shadowOpacity = 0.66
        imageView.layer.shadowOffset = .zero
        
        return imageView
    }()

    override func setIsSelected(_ isSelected: Bool) {
        super.setIsSelected(isSelected)

        if isSelected {
            if let approvalRailCellDelegate = self.approvalRailCellDelegate,
                approvalRailCellDelegate.canRemoveApprovalRailCellView(self) {

                addSubview(deleteButton)
                deleteButton.autoPinEdge(toSuperviewEdge: .top, withInset: cellBorderWidth)
                deleteButton.autoPinEdge(toSuperviewEdge: .trailing, withInset: cellBorderWidth + 4)
            }
        } else {
            deleteButton.removeFromSuperview()
        }
    }

    override func configure(item: GalleryRailItem, delegate: GalleryRailCellViewDelegate) {
        super.configure(item: item, delegate: delegate)

        var hasCaption = false
        if let attachmentItem = item as? SignalAttachmentItem {
            if let captionText = attachmentItem.captionText {
                hasCaption = captionText.count > 0
            }
        } else {
            owsFailDebug("Invalid item.")
        }

        if hasCaption {
            addSubview(captionIndicator)

            captionIndicator.autoPinEdge(toSuperviewEdge: .top, withInset: cellBorderWidth)
            captionIndicator.autoPinEdge(toSuperviewEdge: .leading, withInset: cellBorderWidth + 4)
        } else {
            captionIndicator.removeFromSuperview()
        }
    }
}
