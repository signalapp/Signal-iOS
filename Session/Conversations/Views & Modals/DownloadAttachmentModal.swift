// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
import SessionUIKit
import SessionUtilitiesKit
import SessionMessagingKit

final class DownloadAttachmentModal: Modal {
    private let profile: Profile?

    // MARK: - Lifecycle
    
    init(profile: Profile?) {
        self.profile = profile
        
        super.init(nibName: nil, bundle: nil)
    }

    override init(nibName: String?, bundle: Bundle?) {
        preconditionFailure("Use init(viewItem:) instead.")
    }

    required init?(coder: NSCoder) {
        preconditionFailure("Use init(viewItem:) instead.")
    }

    override func populateContentView() {
        guard let profile: Profile = profile else { return }
        
        // Name
        let name: String = profile.displayName()
        
        // Title
        let titleLabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        titleLabel.text = String(format: NSLocalizedString("modal_download_attachment_title", comment: ""), name)
        titleLabel.textAlignment = .center
        
        // Message
        let messageLabel = UILabel()
        messageLabel.textColor = Colors.text
        messageLabel.font = .systemFont(ofSize: Values.smallFontSize)
        let message = String(format: NSLocalizedString("modal_download_attachment_explanation", comment: ""), name)
        let attributedMessage = NSMutableAttributedString(string: message)
        attributedMessage.addAttributes(
            [.font: UIFont.boldSystemFont(ofSize: Values.smallFontSize) ],
            range: (message as NSString).range(of: name)
        )
        messageLabel.attributedText = attributedMessage
        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.textAlignment = .center
        
        // Download button
        let downloadButton = UIButton()
        downloadButton.set(.height, to: Values.mediumButtonHeight)
        downloadButton.layer.cornerRadius = Modal.buttonCornerRadius
        downloadButton.titleLabel!.font = .systemFont(ofSize: Values.smallFontSize)
        downloadButton.setTitleColor(Colors.text, for: UIControl.State.normal)
        downloadButton.setTitle(NSLocalizedString("modal_download_button_title", comment: ""), for: UIControl.State.normal)
        downloadButton.addTarget(self, action: #selector(trust), for: UIControl.Event.touchUpInside)
        
        // Button stack view
        let buttonStackView = UIStackView(arrangedSubviews: [ cancelButton, downloadButton ])
        buttonStackView.axis = .horizontal
        buttonStackView.spacing = Values.mediumSpacing
        buttonStackView.distribution = .fillEqually
        
        // Content stack view
        let contentStackView = UIStackView(arrangedSubviews: [ titleLabel, messageLabel ])
        contentStackView.axis = .vertical
        contentStackView.spacing = Values.largeSpacing
        
        // Main stack view
        let spacing = Values.largeSpacing - Values.smallFontSize / 2
        let mainStackView = UIStackView(arrangedSubviews: [ contentStackView, buttonStackView ])
        mainStackView.axis = .vertical
        mainStackView.spacing = spacing
        contentView.addSubview(mainStackView)
        mainStackView.pin(.leading, to: .leading, of: contentView, withInset: Values.largeSpacing)
        mainStackView.pin(.top, to: .top, of: contentView, withInset: Values.largeSpacing)
        contentView.pin(.trailing, to: .trailing, of: mainStackView, withInset: Values.largeSpacing)
        contentView.pin(.bottom, to: .bottom, of: mainStackView, withInset: spacing)
    }

    // MARK: - Interaction
    
    @objc private func trust() {
        guard let profileId: String = profile?.id else { return }

        Storage.shared.writeAsync { db in
            try Contact
                .filter(id: profileId)
                .updateAll(db, Contact.Columns.isTrusted.set(to: true))
            
            // Start downloading any pending attachments for this contact (UI will automatically be
            // updated due to the database observation)
            try Attachment
                .stateInfo(authorId: profileId, state: .pendingDownload)
                .fetchAll(db)
                .forEach { attachmentDownloadInfo in
                    JobRunner.add(
                        db,
                        job: Job(
                            variant: .attachmentDownload,
                            threadId: profileId,
                            interactionId: attachmentDownloadInfo.interactionId,
                            details: AttachmentDownloadJob.Details(
                                attachmentId: attachmentDownloadInfo.attachmentId
                            )
                        )
                    )
                }
        }

        presentingViewController?.dismiss(animated: true, completion: nil)
    }
}
