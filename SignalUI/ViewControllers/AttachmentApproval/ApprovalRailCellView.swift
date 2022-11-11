//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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

    private lazy var deleteButton: UIButton = {
        let button = OWSButton { [weak self] in
            guard let strongSelf = self else { return }

            guard let attachmentApprovalItem = strongSelf.item as? AttachmentApprovalItem else {
                owsFailDebug("attachmentApprovalItem was unexpectedly nil")
                return
            }

            strongSelf.approvalRailCellDelegate?.approvalRailCellView(strongSelf, didRemoveItem: attachmentApprovalItem)
        }

        button.alpha = 0
        button.bounds = CGRect(origin: .zero, size: CGSize(square: 24))
        button.setImage(#imageLiteral(resourceName: "media-composer-trash"), for: .normal)
        button.tintColor = .white
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(deleteButton)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        deleteButton.center = bounds.center
    }

    override func setIsSelected(_ isSelected: Bool) {
        super.setIsSelected(isSelected)

        if isSelected {
            if let approvalRailCellDelegate = self.approvalRailCellDelegate,
               approvalRailCellDelegate.canRemoveApprovalRailCellView(self) {

                deleteButton.alpha = 1
                dimmerView.backgroundColor = .ows_blackAlpha50
            }
        } else {
            deleteButton.alpha = 0
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
