// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionMessagingKit

final class InfoMessageCell: MessageCell {
    private static let iconSize: CGFloat = 16
    private static let inset = Values.mediumSpacing
    
    // MARK: - UI
    
    private lazy var iconImageViewWidthConstraint = iconImageView.set(.width, to: InfoMessageCell.iconSize)
    private lazy var iconImageViewHeightConstraint = iconImageView.set(.height, to: InfoMessageCell.iconSize)
    
    private lazy var iconImageView: UIImageView = UIImageView()

    private lazy var label: UILabel = {
        let result: UILabel = UILabel()
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        result.font = .boldSystemFont(ofSize: Values.verySmallFontSize)
        result.textColor = Colors.text
        result.textAlignment = .center
        
        return result
    }()

    private lazy var stackView: UIStackView = {
        let result: UIStackView = UIStackView(arrangedSubviews: [ iconImageView, label ])
        result.axis = .vertical
        result.alignment = .center
        result.spacing = Values.smallSpacing
        
        return result
    }()

    // MARK: - Lifecycle
    
    override func setUpViewHierarchy() {
        super.setUpViewHierarchy()
        
        iconImageViewWidthConstraint.isActive = true
        iconImageViewHeightConstraint.isActive = true
        addSubview(stackView)
        
        stackView.pin(.left, to: .left, of: self, withInset: InfoMessageCell.inset)
        stackView.pin(.top, to: .top, of: self, withInset: InfoMessageCell.inset)
        stackView.pin(.right, to: .right, of: self, withInset: -InfoMessageCell.inset)
        stackView.pin(.bottom, to: .bottom, of: self, withInset: -InfoMessageCell.inset)
    }

    // MARK: - Updating
    
    override func update(with item: ConversationViewModel.Item, mediaCache: NSCache<NSString, AnyObject>, playbackInfo: ConversationViewModel.PlaybackInfo?, lastSearchText: String?) {
        switch item.interactionVariant {
            case .infoClosedGroupCreated, .infoClosedGroupUpdated, .infoClosedGroupCurrentUserLeft,
                .infoDisappearingMessagesUpdate, .infoScreenshotNotification, .infoMediaSavedNotification,
                .infoMessageRequestAccepted:
                break
                
            default: return // Ignore non-info variants
        }
        
        let icon: UIImage? = {
            switch item.interactionVariant {
                case .infoDisappearingMessagesUpdate:
                    return (item.threadHasDisappearingMessagesEnabled ?
                        UIImage(named: "ic_timer") :
                        UIImage(named: "ic_timer_disabled")
                    )
                    
                case .infoMediaSavedNotification: return UIImage(named: "ic_download")
                    
                default: return nil
            }
        }()
        
        if let icon = icon {
            iconImageView.image = icon.withTint(Colors.text)
        }
        
        iconImageViewWidthConstraint.constant = (icon != nil) ? InfoMessageCell.iconSize : 0
        iconImageViewHeightConstraint.constant = (icon != nil) ? InfoMessageCell.iconSize : 0
        
        self.label.text = item.body
    }
    
    override func dynamicUpdate(with item: ConversationViewModel.Item, playbackInfo: ConversationViewModel.PlaybackInfo?) {
    }
}
