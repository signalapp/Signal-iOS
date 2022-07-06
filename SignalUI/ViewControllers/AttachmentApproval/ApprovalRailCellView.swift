//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

protocol ApprovalRailCellViewDelegate: AnyObject {
    func approvalRailCellView(_ approvalRailCellView: ApprovalRailCellView,
                              didRemoveItem attachmentApprovalItem: AttachmentApprovalItem)
    func canRemoveApprovalRailCellView(_ approvalRailCellView: ApprovalRailCellView) -> Bool
}

// MARK: -

class ApprovalRailCellView: GalleryRailCellView {

    weak var approvalRailCellDelegate: ApprovalRailCellViewDelegate?

    lazy var deleteButton: UIButton = {
        let button = OWSButton { [weak self] in
            guard let strongSelf = self else { return }

            guard let attachmentApprovalItem = strongSelf.item as? AttachmentApprovalItem else {
                owsFailDebug("attachmentApprovalItem was unexpectedly nil")
                return
            }

            strongSelf.approvalRailCellDelegate?.approvalRailCellView(strongSelf, didRemoveItem: attachmentApprovalItem)
        }

        button.setImage(#imageLiteral(resourceName: "media-composer-trash"), for: .normal)
        button.tintColor = .white
        button.autoSetDimensions(to: CGSize(square: 24))
        return button
    }()

    override func setIsSelected(_ isSelected: Bool) {
        super.setIsSelected(isSelected)

        if isSelected {
            if let approvalRailCellDelegate = self.approvalRailCellDelegate,
                approvalRailCellDelegate.canRemoveApprovalRailCellView(self) {

                addSubview(deleteButton)
                deleteButton.autoCenterInSuperview()
                dimmerView.backgroundColor = .ows_blackAlpha50
            }
        } else {
            deleteButton.removeFromSuperview()
            dimmerView.backgroundColor = .clear
        }
    }
}

class AddMediaRailCellView: GalleryRailCellView {

    override init(frame: CGRect) {
        super.init(frame: frame)

        dimmerView.isHidden = true
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
