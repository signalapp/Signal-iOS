//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import UIKit

class AttachmentApprovalTopBar: MediaTopBar {

    // MARK: - Subviews

    let cancelButton: UIButton = {
        let button = RoundMediaButton(image: #imageLiteral(resourceName: "media-composer-close"), backgroundStyle: .blur)
        button.accessibilityLabel = CommonStrings.dismissButton
        return button
    }()

    let backButton: UIButton = {
        let backButton = RoundMediaButton(image: UIImage(imageLiteralResourceName: "chevron-left-28"), backgroundStyle: .blur)
        backButton.accessibilityLabel = CommonStrings.backButton
        return backButton
    }()

    private lazy var recipientListView = ExpandableContactListView()

    // MARK: - Updates

    func update(withRecipientNames recipientNames: [String]) {
        guard !recipientNames.isEmpty else {
            recipientListView.isHiddenInStackView = true
            return
        }

        recipientListView.isHiddenInStackView = false
        recipientListView.contactNames = recipientNames
    }

    // MARK: - UIView

    required init(options: AttachmentApprovalViewControllerOptions) {
        super.init(frame: .zero)

        tintColor = .ows_white

        let leadingButton: UIButton
        if options.contains(.hasCancel) {
            leadingButton = cancelButton
        } else {
            leadingButton = backButton
        }
        let spacerView = UIView.hStretchingSpacer()
        let stackView = UIStackView(arrangedSubviews: [ leadingButton, spacerView, recipientListView ])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.alignment = .center
        addSubview(stackView)
        addConstraints([
            leadingButton.layoutMarginsGuide.leadingAnchor.constraint(equalTo: controlsLayoutGuide.leadingAnchor),
            stackView.topAnchor.constraint(equalTo: controlsLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: controlsLayoutGuide.bottomAnchor),
            stackView.trailingAnchor.constraint(equalTo: controlsLayoutGuide.trailingAnchor),
            spacerView.widthAnchor.constraint(greaterThanOrEqualToConstant: 24)
        ])
    }

    @available(*, unavailable, message: "Use init(frame:) instead")
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
