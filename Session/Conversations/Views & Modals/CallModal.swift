// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionMessagingKit

@objc
final class CallModal: Modal {
    private let onCallEnabled: () -> Void

    // MARK: - Lifecycle
    
    @objc
    init(onCallEnabled: @escaping () -> Void) {
        self.onCallEnabled = onCallEnabled
        
        super.init(nibName: nil, bundle: nil)
        
        self.modalPresentationStyle = .overFullScreen
        self.modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        preconditionFailure("Use init(onCallEnabled:) instead.")
    }

    override init(nibName: String?, bundle: Bundle?) {
        preconditionFailure("Use init(onCallEnabled:) instead.")
    }

    override func populateContentView() {
        // Title
        let titleLabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.largeFontSize)
        titleLabel.text = NSLocalizedString("modal_call_title", comment: "")
        titleLabel.textAlignment = .center
        
        // Message
        let messageLabel = UILabel()
        messageLabel.textColor = Colors.text
        messageLabel.font = .systemFont(ofSize: Values.smallFontSize)
        messageLabel.text = "modal_call_explanation".localized()
        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.textAlignment = .center
        
        // Enable button
        let enableButton = UIButton()
        enableButton.set(.height, to: Values.mediumButtonHeight)
        enableButton.layer.cornerRadius = Modal.buttonCornerRadius
        enableButton.backgroundColor = Colors.buttonBackground
        enableButton.titleLabel!.font = .systemFont(ofSize: Values.smallFontSize)
        enableButton.setTitleColor(Colors.text, for: UIControl.State.normal)
        enableButton.setTitle(NSLocalizedString("modal_link_previews_button_title", comment: ""), for: UIControl.State.normal)
        enableButton.addTarget(self, action: #selector(enable), for: UIControl.Event.touchUpInside)
        
        // Button stack view
        let buttonStackView = UIStackView(arrangedSubviews: [ cancelButton, enableButton ])
        buttonStackView.axis = .horizontal
        buttonStackView.spacing = Values.mediumSpacing
        buttonStackView.distribution = .fillEqually
        
        // Main stack view
        let mainStackView = UIStackView(arrangedSubviews: [ titleLabel, messageLabel, buttonStackView ])
        mainStackView.axis = .vertical
        mainStackView.spacing = Values.largeSpacing
        contentView.addSubview(mainStackView)
        
        mainStackView.pin(.leading, to: .leading, of: contentView, withInset: Values.largeSpacing)
        mainStackView.pin(.top, to: .top, of: contentView, withInset: Values.largeSpacing)
        contentView.pin(.trailing, to: .trailing, of: mainStackView, withInset: Values.largeSpacing)
        contentView.pin(.bottom, to: .bottom, of: mainStackView, withInset: Values.largeSpacing)
    }

    // MARK: - Interaction
    
    @objc private func enable() {
        Storage.shared.writeAsync { db in db[.areCallsEnabled] = true }
        presentingViewController?.dismiss(animated: true, completion: nil)
        onCallEnabled()
    }
}
