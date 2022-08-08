// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit

final class CallMissedTipsModal: Modal {
    private let caller: String
    
    // MARK: - Lifecycle
    
    init(caller: String) {
        self.caller = caller
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
        // Tips icon
        let tipsIconImageView = UIImageView(image: UIImage(named: "Tips")?.withTint(Colors.text))
        tipsIconImageView.set(.width, to: 19)
        tipsIconImageView.set(.height, to: 28)
        
        // Tips icon container view
        let tipsIconContainerView = UIView()
        tipsIconContainerView.addSubview(tipsIconImageView)
        tipsIconImageView.pin(.top, to: .top, of: tipsIconContainerView)
        tipsIconImageView.pin(.bottom, to: .bottom, of: tipsIconContainerView)
        tipsIconImageView.center(in: tipsIconContainerView)
        
        // Title
        let titleLabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        titleLabel.text = "modal_call_missed_tips_title".localized()
        titleLabel.textAlignment = .center
        
        // Message
        let messageLabel = UILabel()
        messageLabel.textColor = Colors.text
        messageLabel.font = .systemFont(ofSize: Values.smallFontSize)
        messageLabel.text = String(format: "modal_call_missed_tips_explanation".localized(), caller)
        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.textAlignment = .natural
        
        // Cancel Button
        cancelButton.setTitle("BUTTON_OK".localized(), for: .normal)
        
        // Main stack view
        let mainStackView = UIStackView(arrangedSubviews: [ tipsIconContainerView, titleLabel, messageLabel, cancelButton ])
        mainStackView.axis = .vertical
        mainStackView.alignment = .fill
        mainStackView.spacing = Values.largeSpacing
        contentView.addSubview(mainStackView)
        mainStackView.pin(.leading, to: .leading, of: contentView, withInset: Values.largeSpacing)
        mainStackView.pin(.top, to: .top, of: contentView, withInset: Values.largeSpacing)
        contentView.pin(.trailing, to: .trailing, of: mainStackView, withInset: Values.largeSpacing)
        contentView.pin(.bottom, to: .bottom, of: mainStackView, withInset: Values.largeSpacing)
    }
}
