// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SignalUtilitiesKit

final class UserCell: UITableViewCell {
    // MARK: - Accessory
    
    enum Accessory {
        case none
        case lock
        case tick(isSelected: Bool)
        case x
    }

    // MARK: - Components
    
    private lazy var profilePictureView: ProfilePictureView = ProfilePictureView()

    private lazy var displayNameLabel: UILabel = {
        let result: UILabel = UILabel()
        result.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        result.themeTextColor = .textPrimary
        result.lineBreakMode = .byTruncatingTail
        
        return result
    }()
    
    private let spacer: UIView = {
        let result: UIView = UIView.hStretchingSpacer()
        result.widthAnchor
            .constraint(greaterThanOrEqualToConstant: Values.mediumSpacing)
            .isActive = true
        
        return result
    }()
    
    private let selectionView: RadioButton = {
        let result: RadioButton = RadioButton(size: .medium)
        result.translatesAutoresizingMaskIntoConstraints = false
        result.isUserInteractionEnabled = false
        result.font = .systemFont(ofSize: Values.mediumFontSize, weight: .bold)
        
        return result
    }()

    private lazy var accessoryImageView: UIImageView = {
        let result: UIImageView = UIImageView()
        result.contentMode = .scaleAspectFit
        result.set(.width, to: 24)
        result.set(.height, to: 24)
        
        return result
    }()
    
    private lazy var separator: UIView = {
        let result: UIView = UIView()
        result.themeBackgroundColor = .borderSeparator
        result.set(.height, to: Values.separatorThickness)
        
        return result
    }()

    // MARK: - Initialization
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setUpViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpViewHierarchy()
    }

    private func setUpViewHierarchy() {
        // Highlight color
        let selectedBackgroundView = UIView()
        selectedBackgroundView.themeBackgroundColor = .clear // Disabled for now
        self.selectedBackgroundView = selectedBackgroundView
        
        // Profile picture image view
        let profilePictureViewSize = Values.smallProfilePictureSize
        profilePictureView.set(.width, to: profilePictureViewSize)
        profilePictureView.set(.height, to: profilePictureViewSize)
        profilePictureView.size = profilePictureViewSize
        
        // Main stack view
        let stackView = UIStackView(
            arrangedSubviews: [
                profilePictureView,
                UIView.hSpacer(Values.mediumSpacing),
                displayNameLabel,
                spacer,
                accessoryImageView,
                selectionView
            ]
        )
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = UIEdgeInsets(uniform: Values.mediumSpacing)
        contentView.addSubview(stackView)
        stackView.pin(to: contentView)
        stackView.set(.width, to: UIScreen.main.bounds.width)
        
        // Set up the separator
        contentView.addSubview(separator)
        separator.pin(
            [
                UIView.HorizontalEdge.leading,
                UIView.VerticalEdge.bottom,
                UIView.HorizontalEdge.trailing
            ],
            to: contentView
        )
    }
    
    // MARK: - Updating
    
    func update(
        with publicKey: String,
        profile: Profile?,
        isZombie: Bool,
        mediumFont: Bool = false,
        accessory: Accessory,
        themeBackgroundColor: ThemeValue = .conversationButton_background
    ) {
        self.themeBackgroundColor = themeBackgroundColor
        
        profilePictureView.update(
            publicKey: publicKey,
            profile: profile,
            threadVariant: .contact
        )
        
        displayNameLabel.font = (mediumFont ?
            .systemFont(ofSize: Values.mediumFontSize) :
            .boldSystemFont(ofSize: Values.mediumFontSize)
        )

        displayNameLabel.text = (getUserHexEncodedPublicKey() == publicKey ?
            "MEDIA_GALLERY_SENDER_NAME_YOU".localized() :
            Profile.displayName(
                for: .contact,
                id: publicKey,
                name: profile?.name,
                nickname: profile?.nickname
            )
        )
        
        switch accessory {
            case .none:
                selectionView.isHidden = true
                accessoryImageView.isHidden = true
                displayNameLabel.isHidden = false
                spacer.isHidden = false
            
            case .lock:
                selectionView.isHidden = true
                accessoryImageView.isHidden = false
                accessoryImageView.image = #imageLiteral(resourceName: "ic_lock_outline").withRenderingMode(.alwaysTemplate)
                accessoryImageView.themeTintColor = .textPrimary
                accessoryImageView.alpha = Values.mediumOpacity
                displayNameLabel.isHidden = false
                spacer.isHidden = false
                
            case .tick(let isSelected):
                selectionView.isHidden = false
                selectionView.text = displayNameLabel.text
                selectionView.update(isSelected: isSelected)
                accessoryImageView.isHidden = true
                displayNameLabel.isHidden = true
                spacer.isHidden = true
                
            case .x:
                selectionView.isHidden = true
                accessoryImageView.isHidden = false
                accessoryImageView.image = #imageLiteral(resourceName: "X").withRenderingMode(.alwaysTemplate)
                accessoryImageView.contentMode = .center
                accessoryImageView.themeTintColor = .textPrimary
                accessoryImageView.alpha = 1
                displayNameLabel.isHidden = false
                spacer.isHidden = false
        }
        
        let alpha: CGFloat = (isZombie ? 0.5 : 1)
        [ profilePictureView, displayNameLabel, accessoryImageView, selectionView ]
            .forEach { $0.alpha = alpha }
    }
}
