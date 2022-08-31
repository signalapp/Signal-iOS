// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionMessagingKit

final class CallMessageCell: MessageCell {
    private static let iconSize: CGFloat = 16
    private static let inset = Values.mediumSpacing
    private static let margin = UIScreen.main.bounds.width * 0.1
    
    private lazy var iconImageViewWidthConstraint = iconImageView.set(.width, to: 0)
    private lazy var iconImageViewHeightConstraint = iconImageView.set(.height, to: 0)
    
    private lazy var infoImageViewWidthConstraint = infoImageView.set(.width, to: 0)
    private lazy var infoImageViewHeightConstraint = infoImageView.set(.height, to: 0)
    
    // MARK: - UI
    
    private lazy var iconImageView: UIImageView = UIImageView()
    private lazy var infoImageView: UIImageView = {
        let result: UIImageView = UIImageView(
            image: UIImage(named: "ic_info")?.withRenderingMode(.alwaysTemplate)
        )
        result.themeTintColor = .textPrimary
        
        return result
    }()
    
    private lazy var timestampLabel: UILabel = {
        let result: UILabel = UILabel()
        result.font = .boldSystemFont(ofSize: Values.verySmallFontSize)
        result.themeTextColor = .textPrimary
        result.textAlignment = .center
        
        return result
    }()
    
    private lazy var label: UILabel = {
        let result: UILabel = UILabel()
        result.font = .boldSystemFont(ofSize: Values.smallFontSize)
        result.themeTextColor = .textPrimary
        result.textAlignment = .center
        result.lineBreakMode = .byWordWrapping
        result.numberOfLines = 0
        
        return result
    }()
    
    private lazy var container: UIView = {
        let result: UIView = UIView()
        result.themeBackgroundColor = .backgroundSecondary
        result.set(.height, to: 50)
        result.layer.cornerRadius = 18
        result.addSubview(label)
        
        label.autoCenterInSuperview()
        result.addSubview(iconImageView)
        
        iconImageView.autoVCenterInSuperview()
        iconImageView.pin(.left, to: .left, of: result, withInset: CallMessageCell.inset)
        result.addSubview(infoImageView)
        
        infoImageView.autoVCenterInSuperview()
        infoImageView.pin(.right, to: .right, of: result, withInset: -CallMessageCell.inset)
        
        return result
    }()
    
    private lazy var stackView: UIStackView = {
        let result: UIStackView = UIStackView(arrangedSubviews: [ timestampLabel, container ])
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
        
        container.autoPinWidthToSuperview()
        stackView.pin(.left, to: .left, of: self, withInset: CallMessageCell.margin)
        stackView.pin(.top, to: .top, of: self, withInset: CallMessageCell.inset)
        stackView.pin(.right, to: .right, of: self, withInset: -CallMessageCell.margin)
        stackView.pin(.bottom, to: .bottom, of: self, withInset: -CallMessageCell.inset)
    }
    
    override func setUpGestureRecognizers() {
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tapGestureRecognizer.numberOfTapsRequired = 1
        addGestureRecognizer(tapGestureRecognizer)
    }
    
    // MARK: - Updating
    
    override func update(
        with cellViewModel: MessageViewModel,
        mediaCache: NSCache<NSString, AnyObject>,
        playbackInfo: ConversationViewModel.PlaybackInfo?,
        showExpandedReactions: Bool,
        lastSearchText: String?
    ) {
        guard
            cellViewModel.variant == .infoCall,
            let infoMessageData: Data = (cellViewModel.rawBody ?? "").data(using: .utf8),
            let messageInfo: CallMessage.MessageInfo = try? JSONDecoder().decode(
                CallMessage.MessageInfo.self,
                from: infoMessageData
            )
        else { return }
        
        self.viewModel = cellViewModel
        
        iconImageView.image = {
            switch messageInfo.state {
                case .outgoing: return UIImage(named: "CallOutgoing")?.withRenderingMode(.alwaysTemplate)
                case .incoming: return UIImage(named: "CallIncoming")?.withRenderingMode(.alwaysTemplate)
                case .missed, .permissionDenied: return UIImage(named: "CallMissed")?.withRenderingMode(.alwaysTemplate)
                default: return nil
            }
        }()
        iconImageView.themeTintColor = {
            switch messageInfo.state {
                case .outgoing, .incoming: return .textPrimary
                case .missed, .permissionDenied: return .danger
                default: return nil
            }
        }()
        iconImageViewWidthConstraint.constant = (iconImageView.image != nil ? CallMessageCell.iconSize : 0)
        iconImageViewHeightConstraint.constant = (iconImageView.image != nil ? CallMessageCell.iconSize : 0)
        
        let shouldShowInfoIcon: Bool = (
            messageInfo.state == .permissionDenied &&
            !Storage.shared[.areCallsEnabled]
        )
        infoImageViewWidthConstraint.constant = (shouldShowInfoIcon ? CallMessageCell.iconSize : 0)
        infoImageViewHeightConstraint.constant = (shouldShowInfoIcon ? CallMessageCell.iconSize : 0)
        
        label.text = cellViewModel.body
        timestampLabel.text = cellViewModel.dateForUI?.formattedForDisplay
    }
    
    override func dynamicUpdate(with cellViewModel: MessageViewModel, playbackInfo: ConversationViewModel.PlaybackInfo?) {
    }
    
    @objc private func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        guard
            let cellViewModel: MessageViewModel = self.viewModel,
            cellViewModel.variant == .infoCall,
            let infoMessageData: Data = (cellViewModel.rawBody ?? "").data(using: .utf8),
            let messageInfo: CallMessage.MessageInfo = try? JSONDecoder().decode(
                CallMessage.MessageInfo.self,
                from: infoMessageData
            )
        else { return }
        
        // Should only be tappable if the info icon is visible
        guard messageInfo.state == .permissionDenied && !Storage.shared[.areCallsEnabled] else { return }
        
        self.delegate?.handleItemTapped(cellViewModel, gestureRecognizer: gestureRecognizer)
    }
}
