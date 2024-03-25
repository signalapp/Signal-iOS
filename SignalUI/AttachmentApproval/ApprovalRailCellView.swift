//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

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
        button.setImage(UIImage(imageLiteralResourceName: "trash-20"), for: .normal)
        button.tintColor = .white
        return button
    }()

    init() {
        let configuration = GalleryRailCellConfiguration(
            cornerRadius: 10,
            itemBorderWidth: 1.5,
            itemBorderColor: .white,
            focusedItemBorderWidth: 2,
            focusedItemBorderColor: Theme.accentBlueColor,
            focusedItemOverlayColor: .ows_blackAlpha50
        )
        super.init(configuration: configuration)
        addSubview(deleteButton)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        deleteButton.center = bounds.center
    }

    override var isCellFocused: Bool {
        didSet {
            if isCellFocused, let approvalRailCellDelegate, approvalRailCellDelegate.canRemoveApprovalRailCellView(self) {
                deleteButton.alpha = 1
            } else {
                deleteButton.alpha = 0
            }
        }
    }
}

class AddMediaRailCellView: GalleryRailCellView {

    init() {
        super.init(configuration: .empty)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
