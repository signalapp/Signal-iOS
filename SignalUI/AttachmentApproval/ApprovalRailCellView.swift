//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

protocol ApprovalRailCellViewDelegate: AnyObject {
    func approvalRailCellView(
        _ approvalRailCellView: ApprovalRailCellView,
        didRemoveItem attachmentApprovalItem: AttachmentApprovalItem,
    )
    func canRemoveApprovalRailCellView(_ approvalRailCellView: ApprovalRailCellView) -> Bool
}

// MARK: -

class ApprovalRailCellView: GalleryRailCellView {

    weak var approvalRailCellDelegate: ApprovalRailCellViewDelegate?

    private lazy var deleteButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(imageLiteralResourceName: "trash")
        configuration.contentInsets = .init(margin: 4)
        let button = UIButton(
            configuration: configuration,
            primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                guard let attachmentApprovalItem = self.item as? AttachmentApprovalItem else {
                    owsFailDebug("attachmentApprovalItem was unexpectedly nil")
                    return
                }
                self.approvalRailCellDelegate?.approvalRailCellView(self, didRemoveItem: attachmentApprovalItem)
            },
        )
        button.tintColor = .white // fixed color
        button.alpha = 0
        return button
    }()

    init() {
        // On iOS 26 selected thumbnail doesn't have a border, but instead
        // it has some extra space around it. Similar to what Photos app does.
        let cornerRadius: CGFloat
        let borderColor: UIColor
        let focusedBorderColor: UIColor
        let borderWidth: CGFloat
        let focusedBorderWidth: CGFloat
        let extraPadding: CGFloat
        if #available(iOS 26, *) {
            cornerRadius = 8
            borderColor = .clear
            focusedBorderColor = .clear
            borderWidth = 0
            focusedBorderWidth = 0
            extraPadding = 8
        } else {
            cornerRadius = 10
            borderColor = .white
            focusedBorderColor = .Signal.accent
            borderWidth = 1.5
            focusedBorderWidth = 2
            extraPadding = 0
        }
        let configuration = GalleryRailCellConfiguration(
            cornerRadius: cornerRadius,
            itemBorderWidth: borderWidth,
            itemBorderColor: borderColor,
            focusedItemBorderWidth: focusedBorderWidth,
            focusedItemBorderColor: focusedBorderColor,
            focusedItemOverlayColor: .ows_blackAlpha40,
            focusedItemExtraPadding: extraPadding,
        )
        super.init(configuration: configuration)

        deleteButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(deleteButton)

        NSLayoutConstraint.activate([
            deleteButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
