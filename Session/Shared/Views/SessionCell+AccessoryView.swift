// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit
import SignalUtilitiesKit

extension SessionCell {
    public class AccessoryView: UIView {
        // MARK: - UI
        
        private lazy var imageViewConstraints: [NSLayoutConstraint] = [
            imageView.pin(.top, to: .top, of: self),
            imageView.pin(.leading, to: .leading, of: self),
            imageView.pin(.trailing, to: .trailing, of: self),
            imageView.pin(.bottom, to: .bottom, of: self)
        ]
        private lazy var imageViewWidthConstraint: NSLayoutConstraint = imageView.set(.width, to: 0)
        private lazy var imageViewHeightConstraint: NSLayoutConstraint = imageView.set(.height, to: 0)
        private lazy var toggleSwitchConstraints: [NSLayoutConstraint] = [
            toggleSwitch.pin(.top, to: .top, of: self),
            toggleSwitch.pin(.leading, to: .leading, of: self),
            toggleSwitch.pin(.trailing, to: .trailing, of: self),
            toggleSwitch.pin(.bottom, to: .bottom, of: self)
        ]
        private lazy var dropDownStackViewConstraints: [NSLayoutConstraint] = [
            dropDownStackView.pin(.top, to: .top, of: self),
            dropDownStackView.pin(.leading, to: .leading, of: self),
            dropDownStackView.pin(.trailing, to: .trailing, of: self),
            dropDownStackView.pin(.bottom, to: .bottom, of: self)
        ]
        private lazy var radioViewWidthConstraint: NSLayoutConstraint = radioView.set(.width, to: 0)
        private lazy var radioViewHeightConstraint: NSLayoutConstraint = radioView.set(.height, to: 0)
        private lazy var radioBorderViewWidthConstraint: NSLayoutConstraint = radioBorderView.set(.width, to: 0)
        private lazy var radioBorderViewHeightConstraint: NSLayoutConstraint = radioBorderView.set(.height, to: 0)
        private lazy var radioBorderViewConstraints: [NSLayoutConstraint] = [
            radioBorderView.pin(.top, to: .top, of: self),
            radioBorderView.pin(.leading, to: .leading, of: self),
            radioBorderView.pin(.trailing, to: .trailing, of: self),
            radioBorderView.pin(.bottom, to: .bottom, of: self)
        ]
        private lazy var highlightingBackgroundLabelConstraints: [NSLayoutConstraint] = [
            highlightingBackgroundLabel.pin(.top, to: .top, of: self),
            highlightingBackgroundLabel.pin(.leading, to: .leading, of: self),
            highlightingBackgroundLabel.pin(.trailing, to: .trailing, of: self),
            highlightingBackgroundLabel.pin(.bottom, to: .bottom, of: self)
        ]
        private lazy var profilePictureViewConstraints: [NSLayoutConstraint] = [
            profilePictureView.pin(.top, to: .top, of: self),
            profilePictureView.pin(.leading, to: .leading, of: self),
            profilePictureView.pin(.trailing, to: .trailing, of: self),
            profilePictureView.pin(.bottom, to: .bottom, of: self)
        ]
        
        private let imageView: UIImageView = {
            let result: UIImageView = UIImageView()
            result.translatesAutoresizingMaskIntoConstraints = false
            result.clipsToBounds = true
            result.contentMode = .scaleAspectFit
            result.themeTintColor = .textPrimary
            result.layer.minificationFilter = .trilinear
            result.layer.magnificationFilter = .trilinear
            result.isHidden = true
            
            return result
        }()
        
        private let toggleSwitch: UISwitch = {
            let result: UISwitch = UISwitch()
            result.translatesAutoresizingMaskIntoConstraints = false
            result.isUserInteractionEnabled = false // Triggered by didSelectCell instead
            result.themeOnTintColor = .primary
            result.isHidden = true
            result.setContentHuggingHigh()
            result.setCompressionResistanceHigh()
            
            return result
        }()
        
        private let dropDownStackView: UIStackView = {
            let result: UIStackView = UIStackView()
            result.translatesAutoresizingMaskIntoConstraints = false
            result.axis = .horizontal
            result.distribution = .fill
            result.alignment = .center
            result.spacing = Values.verySmallSpacing
            result.isHidden = true
            
            return result
        }()
        
        private let dropDownImageView: UIImageView = {
            let result: UIImageView = UIImageView(image: UIImage(systemName: "arrowtriangle.down.fill"))
            result.translatesAutoresizingMaskIntoConstraints = false
            result.themeTintColor = .textPrimary
            result.set(.width, to: 10)
            result.set(.height, to: 10)
            
            return result
        }()
        
        private let dropDownLabel: UILabel = {
            let result: UILabel = UILabel()
            result.translatesAutoresizingMaskIntoConstraints = false
            result.font = .systemFont(ofSize: Values.smallFontSize, weight: .medium)
            result.themeTextColor = .textPrimary
            result.setContentHuggingHigh()
            result.setCompressionResistanceHigh()
            
            return result
        }()
        
        private let radioBorderView: UIView = {
            let result: UIView = UIView()
            result.translatesAutoresizingMaskIntoConstraints = false
            result.isUserInteractionEnabled = false
            result.layer.borderWidth = 1
            result.themeBorderColor = .radioButton_unselectedBorder
            result.isHidden = true
            
            return result
        }()
        
        private let radioView: UIView = {
            let result: UIView = UIView()
            result.translatesAutoresizingMaskIntoConstraints = false
            result.isUserInteractionEnabled = false
            result.themeBackgroundColor = .radioButton_unselectedBackground
            result.isHidden = true
            
            return result
        }()
        
        public lazy var highlightingBackgroundLabel: SessionHighlightingBackgroundLabel = {
            let result: SessionHighlightingBackgroundLabel = SessionHighlightingBackgroundLabel()
            result.translatesAutoresizingMaskIntoConstraints = false
            result.isHidden = true
            
            return result
        }()
        
        private lazy var profilePictureView: ProfilePictureView = {
            let result: ProfilePictureView = ProfilePictureView()
            result.translatesAutoresizingMaskIntoConstraints = false
            result.size = Values.smallProfilePictureSize
            result.isHidden = true
            result.set(.width, to: Values.smallProfilePictureSize)
            result.set(.height, to: Values.smallProfilePictureSize)
            
            return result
        }()
        
        private var customView: UIView?
        
        // MARK: - Initialization
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            
            setupViewHierarchy()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            
            setupViewHierarchy()
        }

        private func setupViewHierarchy() {
            addSubview(imageView)
            addSubview(toggleSwitch)
            addSubview(dropDownStackView)
            addSubview(radioBorderView)
            addSubview(highlightingBackgroundLabel)
            addSubview(profilePictureView)
            
            dropDownStackView.addArrangedSubview(dropDownImageView)
            dropDownStackView.addArrangedSubview(dropDownLabel)
            
            radioBorderView.addSubview(radioView)
            radioView.center(in: radioBorderView)
        }
        
        // MARK: - Content
        
        func prepareForReuse() {
            self.isHidden = true
            
            imageView.image = nil
            imageView.themeTintColor = .textPrimary
            imageView.contentMode = .scaleAspectFit
            dropDownImageView.themeTintColor = .textPrimary
            dropDownLabel.text = ""
            dropDownLabel.themeTextColor = .textPrimary
            radioBorderView.themeBorderColor = .radioButton_unselectedBorder
            radioView.themeBackgroundColor = .radioButton_unselectedBackground
            highlightingBackgroundLabel.text = ""
            highlightingBackgroundLabel.themeTextColor = .textPrimary
            customView?.removeFromSuperview()
            
            imageView.isHidden = true
            toggleSwitch.isHidden = true
            dropDownStackView.isHidden = true
            radioBorderView.isHidden = true
            radioView.alpha = 1
            radioView.isHidden = true
            highlightingBackgroundLabel.isHidden = true
            profilePictureView.isHidden = true
            
            imageViewWidthConstraint.isActive = false
            imageViewHeightConstraint.isActive = false
            imageViewConstraints.forEach { $0.isActive = false }
            toggleSwitchConstraints.forEach { $0.isActive = false }
            dropDownStackViewConstraints.forEach { $0.isActive = false }
            radioViewWidthConstraint.isActive = false
            radioViewHeightConstraint.isActive = false
            radioBorderViewWidthConstraint.isActive = false
            radioBorderViewHeightConstraint.isActive = false
            radioBorderViewConstraints.forEach { $0.isActive = false }
            highlightingBackgroundLabelConstraints.forEach { $0.isActive = false }
            profilePictureViewConstraints.forEach { $0.isActive = false }
        }
        
        public func update(
            with accessory: Accessory?,
            tintColor: ThemeValue,
            isEnabled: Bool
        ) {
            guard let accessory: Accessory = accessory else { return }
            
            // If we have an accessory value then this shouldn't be hidden
            self.isHidden = false

            switch accessory {
                case .icon(let image, let iconSize, let customTint, let shouldFill):
                    imageView.image = image
                    imageView.themeTintColor = (customTint ?? tintColor)
                    imageView.contentMode = (shouldFill ? .scaleAspectFill : .scaleAspectFit)
                    imageView.isHidden = false
                    
                    switch iconSize {
                        case .fit:
                            imageView.sizeToFit()
                            imageViewWidthConstraint.constant = imageView.bounds.width
                            imageViewHeightConstraint.constant = imageView.bounds.height

                        default:
                            imageViewWidthConstraint.constant = iconSize.size
                            imageViewHeightConstraint.constant = iconSize.size
                    }
                    
                    imageViewWidthConstraint.isActive = true
                    imageViewHeightConstraint.isActive = true
                    imageViewConstraints.forEach { $0.isActive = true }
                
                case .iconAsync(let iconSize, let customTint, let shouldFill, let setter):
                    setter(imageView)
                    imageView.themeTintColor = (customTint ?? tintColor)
                    imageView.contentMode = (shouldFill ? .scaleAspectFill : .scaleAspectFit)
                    imageView.isHidden = false
                    
                    switch iconSize {
                        case .fit:
                            imageView.sizeToFit()
                            imageViewWidthConstraint.constant = imageView.bounds.width
                            imageViewHeightConstraint.constant = imageView.bounds.height

                        default:
                            imageViewWidthConstraint.constant = iconSize.size
                            imageViewHeightConstraint.constant = iconSize.size
                    }
                    
                    imageViewWidthConstraint.isActive = true
                    imageViewHeightConstraint.isActive = true
                    imageViewConstraints.forEach { $0.isActive = true }
                    
                case .toggle(let dataSource):
                    toggleSwitch.isHidden = false
                    toggleSwitch.isEnabled = isEnabled
                    toggleSwitchConstraints.forEach { $0.isActive = true }
                    
                    let newValue: Bool = dataSource.currentBoolValue
                    
                    if newValue != toggleSwitch.isOn {
                        toggleSwitch.setOn(newValue, animated: true)
                    }
                    
                case .dropDown(let dataSource):
                    dropDownLabel.text = dataSource.currentStringValue
                    dropDownStackView.isHidden = false
                    dropDownStackViewConstraints.forEach { $0.isActive = true }
                    
                case .radio(let size, let isSelectedRetriever, let storedSelection):
                    let isSelected: Bool = isSelectedRetriever()
                    let wasOldSelection: Bool = (!isSelected && storedSelection)
                    
                    radioBorderView.isHidden = false
                    radioBorderView.themeBorderColor = (isSelected ?
                        .radioButton_selectedBorder :
                        .radioButton_unselectedBorder
                    )
                    radioBorderView.layer.cornerRadius = (size.borderSize / 2)
                    
                    radioView.alpha = (wasOldSelection ? 0.3 : 1)
                    radioView.isHidden = (!isSelected && !storedSelection)
                    radioView.themeBackgroundColor = (isSelected || wasOldSelection ?
                        .radioButton_selectedBackground :
                        .radioButton_unselectedBackground
                    )
                    radioView.layer.cornerRadius = (size.selectionSize / 2)
                    
                    radioViewWidthConstraint.constant = size.selectionSize
                    radioViewHeightConstraint.constant = size.selectionSize
                    radioBorderViewWidthConstraint.constant = size.borderSize
                    radioBorderViewHeightConstraint.constant = size.borderSize
                    
                    radioViewWidthConstraint.isActive = true
                    radioViewHeightConstraint.isActive = true
                    radioBorderViewWidthConstraint.isActive = true
                    radioBorderViewHeightConstraint.isActive = true
                    radioBorderViewConstraints.forEach { $0.isActive = true }
                    
                case .highlightingBackgroundLabel(let title):
                    highlightingBackgroundLabel.text = title
                    highlightingBackgroundLabel.themeTextColor = tintColor
                    highlightingBackgroundLabel.isHidden = false
                    highlightingBackgroundLabelConstraints.forEach { $0.isActive = true }
                    
                case .profile(let profileId, let profile):
                    profilePictureView.update(
                        publicKey: profileId,
                        profile: profile,
                        threadVariant: .contact
                    )
                    profilePictureView.isHidden = false
                    profilePictureViewConstraints.forEach { $0.isActive = true }
                    
                case .customView(let viewGenerator):
                    let generatedView: UIView = viewGenerator()
                    addSubview(generatedView)
                    
                    generatedView.pin(.top, to: .top, of: self)
                    generatedView.pin(.leading, to: .leading, of: self)
                    generatedView.pin(.trailing, to: .trailing, of: self)
                    generatedView.pin(.bottom, to: .bottom, of: self)
                    
                    self.customView?.removeFromSuperview()  // Just in case
                    self.customView = generatedView
                
                case .threadInfo: break
            }
        }
        
        // MARK: - Interaction
        
        func setHighlighted(_ highlighted: Bool, animated: Bool) {
            highlightingBackgroundLabel.setHighlighted(highlighted, animated: animated)
        }
        
        func setSelected(_ selected: Bool, animated: Bool) {
            highlightingBackgroundLabel.setSelected(selected, animated: animated)
        }
    }

}
