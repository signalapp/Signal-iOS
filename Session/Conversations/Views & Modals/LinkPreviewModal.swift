// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
import SessionUIKit
import SessionMessagingKit

final class LinkPreviewModal: Modal {
    private let onLinkPreviewsEnabled: () -> Void

    // MARK: - Lifecycle
    
    init(onLinkPreviewsEnabled: @escaping () -> Void) {
        self.onLinkPreviewsEnabled = onLinkPreviewsEnabled
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        preconditionFailure("Use init(onLinkPreviewsEnabled:) instead.")
    }

    override init(nibName: String?, bundle: Bundle?) {
        preconditionFailure("Use init(onLinkPreviewsEnabled:) instead.")
    }

    override func populateContentView() {
        // Title
        let titleLabel: UILabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        titleLabel.text = "modal_link_previews_title".localized()
        titleLabel.textAlignment = .center
        
        // Message
        let messageLabel: UILabel = UILabel()
        messageLabel.textColor = Colors.text
        messageLabel.font = .systemFont(ofSize: Values.smallFontSize)
        messageLabel.text = "modal_link_previews_explanation".localized()
        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.textAlignment = .center
        
        // Enable button
        let enableButton: UIButton = UIButton()
        enableButton.set(.height, to: Values.mediumButtonHeight)
        enableButton.layer.cornerRadius = Modal.buttonCornerRadius
        enableButton.backgroundColor = Colors.buttonBackground
        enableButton.titleLabel!.font = .systemFont(ofSize: Values.smallFontSize)
        enableButton.setTitleColor(Colors.text, for: UIControl.State.normal)
        enableButton.setTitle(NSLocalizedString("modal_link_previews_button_title", comment: ""), for: UIControl.State.normal)
        enableButton.addTarget(self, action: #selector(enable), for: UIControl.Event.touchUpInside)
        
        // Button stack view
        let buttonStackView: UIStackView = UIStackView(arrangedSubviews: [ cancelButton, enableButton ])
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
    
    @objc private func enable() {
        Storage.shared.writeAsync { db in
            db[.areLinkPreviewsEnabled] = true
        }
        
        presentingViewController?.dismiss(animated: true, completion: nil)
        onLinkPreviewsEnabled()
    }
}
