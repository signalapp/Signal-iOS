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
        case o(isSelected: Bool)
        case x
    }

    // MARK: - Components
    
    private lazy var profilePictureView: ProfilePictureView = ProfilePictureView()

    private lazy var displayNameLabel: UILabel = {
        let result: UILabel = UILabel()
        result.textColor = Colors.text
        result.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        result.lineBreakMode = .byTruncatingTail
        
        return result
    }()

    private lazy var accessoryImageView: UIImageView = {
        let result: UIImageView = UIImageView()
        result.contentMode = .scaleAspectFit
        result.set(.width, to: 24)
        result.set(.height, to: 24)
        
        return result
    }()
    
    private lazy var roundSelectionView = RoundSelectionView()

    private lazy var separator: UIView = {
        let result: UIView = UIView()
        result.backgroundColor = Colors.separator
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
        // Background color
        backgroundColor = Colors.cellBackground
        
        // Highlight color
        let selectedBackgroundView = UIView()
        selectedBackgroundView.backgroundColor = .clear // Disabled for now
        self.selectedBackgroundView = selectedBackgroundView
        
        // Profile picture image view
        let profilePictureViewSize = Values.smallProfilePictureSize
        profilePictureView.set(.width, to: profilePictureViewSize)
        profilePictureView.set(.height, to: profilePictureViewSize)
        profilePictureView.size = profilePictureViewSize
        
        // Main stack view
        let spacer = UIView.hStretchingSpacer()
        spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: Values.mediumSpacing).isActive = true
        let stackView = UIStackView(
            arrangedSubviews: [
                profilePictureView,
                UIView.hSpacer(Values.mediumSpacing),
                displayNameLabel,
                spacer,
                accessoryImageView,
                roundSelectionView
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
        accessory: Accessory
    ) {
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
                accessoryImageView.isHidden = true
                roundSelectionView.isHidden = true
            case .lock:
                roundSelectionView.isHidden = true
                accessoryImageView.isHidden = false
                accessoryImageView.image = #imageLiteral(resourceName: "ic_lock_outline").withRenderingMode(.alwaysTemplate)
                accessoryImageView.tintColor = Colors.text.withAlphaComponent(Values.mediumOpacity)
                
            case .tick(let isSelected):
                roundSelectionView.isHidden = true
                let icon: UIImage = (isSelected ? #imageLiteral(resourceName: "CircleCheck") : #imageLiteral(resourceName: "Circle"))
                accessoryImageView.isHidden = false
                accessoryImageView.image = icon.withRenderingMode(.alwaysTemplate)
                accessoryImageView.tintColor = Colors.text
            case .x:
                roundSelectionView.isHidden = true
                accessoryImageView.isHidden = false
                accessoryImageView.image = #imageLiteral(resourceName: "X").withRenderingMode(.alwaysTemplate)
                accessoryImageView.contentMode = .center
                accessoryImageView.tintColor = Colors.text
            case .o(let isSelected):
                accessoryImageView.isHidden = true
                roundSelectionView.isHidden = false
                roundSelectionView.update(isSelected: isSelected)
        }
        
        let alpha: CGFloat = (isZombie ? 0.5 : 1)
        [ profilePictureView, displayNameLabel, accessoryImageView ].forEach { $0.alpha = alpha }
    }
}

fileprivate class RoundSelectionView: UIView {
    
    private lazy var centralView: UIView = {
        let result = UIView()
        result.backgroundColor = Colors.accent
        return result
    }()
    
    init() {
        super.init(frame: CGRect.zero)
        self.addSubview(centralView)
        self.set(.width, to: 20)
        self.set(.height, to: 20)
        self.layer.cornerRadius = 10
        self.layer.borderWidth = 1
        self.layer.borderColor = Colors.text.cgColor
        
        centralView.pin(to: self, withInset: 3)
        centralView.layer.cornerRadius = 7
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func update(isSelected: Bool) {
        centralView.isHidden = !isSelected
    }
}
