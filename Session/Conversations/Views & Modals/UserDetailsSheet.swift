// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionMessagingKit

final class UserDetailsSheet: Sheet {
    private let profile: Profile
    
    init(for profile: Profile) {
        self.profile = profile
        
        super.init(nibName: nil, bundle: nil)
    }
    
    override init(nibName: String?, bundle: Bundle?) {
        preconditionFailure("Use init(for:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(for:) instead.")
    }
    
    override func populateContentView() {
        // Profile picture view
        let profilePictureView = ProfilePictureView()
        let size = Values.largeProfilePictureSize
        profilePictureView.size = size
        profilePictureView.set(.width, to: size)
        profilePictureView.set(.height, to: size)
        profilePictureView.update(
            publicKey: profile.id,
            profile: profile,
            threadVariant: .contact
        )
        
        // Display name label
        let displayNameLabel = UILabel()
        let displayName = profile.displayName()
        displayNameLabel.text = displayName
        displayNameLabel.font = .boldSystemFont(ofSize: Values.largeFontSize)
        displayNameLabel.textColor = Colors.text
        displayNameLabel.numberOfLines = 1
        displayNameLabel.lineBreakMode = .byTruncatingTail
        
        // Session ID label
        let sessionIDLabel = UILabel()
        sessionIDLabel.textColor = Colors.text
        sessionIDLabel.font = Fonts.spaceMono(ofSize: isIPhone5OrSmaller ? Values.mediumFontSize : 20)
        sessionIDLabel.numberOfLines = 0
        sessionIDLabel.lineBreakMode = .byCharWrapping
        sessionIDLabel.accessibilityLabel = "Session ID label"
        sessionIDLabel.text = profile.id
        
        // Session ID label container
        let sessionIDLabelContainer = UIView()
        sessionIDLabelContainer.addSubview(sessionIDLabel)
        sessionIDLabel.pin(to: sessionIDLabelContainer, withInset: Values.mediumSpacing)
        sessionIDLabelContainer.layer.cornerRadius = TextField.cornerRadius
        sessionIDLabelContainer.layer.borderWidth = 1
        sessionIDLabelContainer.layer.borderColor = isLightMode ? UIColor.black.cgColor : UIColor.white.cgColor
        
        // Copy button
        let copyButton = Button(style: .prominentOutline, size: .medium)
        copyButton.setTitle(NSLocalizedString("copy", comment: ""), for: UIControl.State.normal)
        copyButton.addTarget(self, action: #selector(copySessionID), for: UIControl.Event.touchUpInside)
        copyButton.set(.width, to: 160)
        
        // Stack view
        let stackView = UIStackView(arrangedSubviews: [ profilePictureView, displayNameLabel, sessionIDLabelContainer, copyButton, UIView.vSpacer(Values.largeSpacing) ])
        stackView.axis = .vertical
        stackView.spacing = Values.largeSpacing
        stackView.alignment = .center
        
        // Constraints
        contentView.addSubview(stackView)
        stackView.pin(to: contentView, withInset: Values.largeSpacing)
    }
    
    @objc private func copySessionID() {
        UIPasteboard.general.string = profile.id
        presentingViewController?.dismiss(animated: true, completion: nil)
    }
}
