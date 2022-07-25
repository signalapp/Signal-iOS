// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionMessagingKit

final class OpenGroupInvitationView: UIView {
    private static let iconSize: CGFloat = 24
    private static let iconImageViewSize: CGFloat = 48
    
    // MARK: - Lifecycle
    
    init(name: String, url: String, textColor: UIColor, isOutgoing: Bool) {
        super.init(frame: CGRect.zero)
        
        setUpViewHierarchy(
            name: name,
            rawUrl: url,
            textColor: textColor,
            isOutgoing: isOutgoing
        )
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(name:url:textColor:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(name:url:textColor:) instead.")
    }
    
    private func setUpViewHierarchy(name: String, rawUrl: String, textColor: UIColor, isOutgoing: Bool) {
        // Title
        let titleLabel = UILabel()
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.text = name
        titleLabel.textColor = textColor
        titleLabel.font = .boldSystemFont(ofSize: Values.largeFontSize)
        
        // Subtitle
        let subtitleLabel = UILabel()
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.text = NSLocalizedString("view_open_group_invitation_description", comment: "")
        subtitleLabel.textColor = textColor
        subtitleLabel.font = .systemFont(ofSize: Values.smallFontSize)
        
        // URL
        let urlLabel = UILabel()
        urlLabel.lineBreakMode = .byCharWrapping
        urlLabel.text = {
            if let range = rawUrl.range(of: "?public_key=") {
                return String(rawUrl[..<range.lowerBound])
            }

            return rawUrl
        }()
        urlLabel.textColor = textColor
        urlLabel.numberOfLines = 0
        urlLabel.font = .systemFont(ofSize: Values.verySmallFontSize)
        
        // Label stack
        let labelStackView = UIStackView(arrangedSubviews: [ titleLabel, UIView.vSpacer(2), subtitleLabel, UIView.vSpacer(4), urlLabel ])
        labelStackView.axis = .vertical
        
        // Icon
        let iconSize = OpenGroupInvitationView.iconSize
        let iconName = (isOutgoing ? "Globe" : "Plus")
        let iconImageViewSize = OpenGroupInvitationView.iconImageViewSize
        let iconImageView = UIImageView(
            image: UIImage(named: iconName)?
                .withRenderingMode(.alwaysTemplate)
                .resizedImage(to: CGSize(width: iconSize, height: iconSize))
        )
        iconImageView.tintColor = .white
        iconImageView.contentMode = .center
        iconImageView.layer.cornerRadius = iconImageViewSize / 2
        iconImageView.layer.masksToBounds = true
        iconImageView.backgroundColor = Colors.accent
        iconImageView.set(.width, to: iconImageViewSize)
        iconImageView.set(.height, to: iconImageViewSize)
        
        // Main stack
        let mainStackView = UIStackView(arrangedSubviews: [ iconImageView, labelStackView ])
        mainStackView.axis = .horizontal
        mainStackView.spacing = Values.mediumSpacing
        mainStackView.alignment = .center
        addSubview(mainStackView)
        mainStackView.pin(to: self, withInset: Values.mediumSpacing)
    }
}
