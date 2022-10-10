// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionMessagingKit

final class CallMessageCell: MessageCell {
    private static let iconSize: CGFloat = 16
    private static let inset = Values.mediumSpacing
    private static let margin = UIScreen.main.bounds.width * 0.1
    
    private var isHandlingLongPress: Bool = false
    
    override var contextSnapshotView: UIView? { return container }
    
    // MARK: - UI
    
    private lazy var topConstraint: NSLayoutConstraint = container.pin(.top, to: .top, of: self, withInset: CallMessageCell.inset)
    private lazy var iconImageViewWidthConstraint: NSLayoutConstraint = iconImageView.set(.width, to: 0)
    private lazy var iconImageViewHeightConstraint: NSLayoutConstraint = iconImageView.set(.height, to: 0)
    private lazy var infoImageViewWidthConstraint: NSLayoutConstraint = infoImageView.set(.width, to: 0)
    private lazy var infoImageViewHeightConstraint: NSLayoutConstraint = infoImageView.set(.height, to: 0)
    
    private lazy var iconImageView: UIImageView = UIImageView()
    private lazy var infoImageView: UIImageView = {
        let result: UIImageView = UIImageView(
            image: UIImage(named: "ic_info")?
                .withRenderingMode(.alwaysTemplate)
        )
        result.themeTintColor = .textPrimary
        
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
        result.layer.cornerRadius = 18
        result.addSubview(label)
        
        label.pin(.top, to: .top, of: result, withInset: CallMessageCell.inset)
        label.pin(
            .left,
            to: .left,
            of: result,
            withInset: ((CallMessageCell.inset * 2) + infoImageView.bounds.size.width)
        )
        label.pin(
            .right,
            to: .right,
            of: result,
            withInset: -((CallMessageCell.inset * 2) + infoImageView.bounds.size.width)
        )
        label.pin(.bottom, to: .bottom, of: result, withInset: -CallMessageCell.inset)
        result.addSubview(iconImageView)
        
        iconImageView.autoVCenterInSuperview()
        iconImageView.pin(.left, to: .left, of: result, withInset: CallMessageCell.inset)
        result.addSubview(infoImageView)
        
        infoImageView.autoVCenterInSuperview()
        infoImageView.pin(.right, to: .right, of: result, withInset: -CallMessageCell.inset)
        
        return result
    }()
    
    // MARK: - Lifecycle
    
    override func setUpViewHierarchy() {
        super.setUpViewHierarchy()
        
        iconImageViewWidthConstraint.isActive = true
        iconImageViewHeightConstraint.isActive = true
        addSubview(container)
        
        topConstraint.isActive = true
        container.pin(.left, to: .left, of: self, withInset: CallMessageCell.margin)
        container.pin(.right, to: .right, of: self, withInset: -CallMessageCell.margin)
        container.pin(.bottom, to: .bottom, of: self, withInset: -CallMessageCell.inset)
    }
    
    override func setUpGestureRecognizers() {
        let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        addGestureRecognizer(longPressRecognizer)
        
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
        self.topConstraint.constant = (cellViewModel.shouldShowDateHeader ? 0 : CallMessageCell.inset)
        
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
    }
    
    override func dynamicUpdate(with cellViewModel: MessageViewModel, playbackInfo: ConversationViewModel.PlaybackInfo?) {
    }
    
    // MARK: - Interaction
    
    @objc func handleLongPress(_ gestureRecognizer: UITapGestureRecognizer) {
        if [ .ended, .cancelled, .failed ].contains(gestureRecognizer.state) {
            isHandlingLongPress = false
            return
        }
        guard !isHandlingLongPress, let cellViewModel: MessageViewModel = self.viewModel else { return }
        
        delegate?.handleItemLongPressed(cellViewModel)
        isHandlingLongPress = true
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
