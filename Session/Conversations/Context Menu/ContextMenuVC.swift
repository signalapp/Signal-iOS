// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionMessagingKit

final class ContextMenuVC: UIViewController {
    private static let actionViewHeight: CGFloat = 40
    private static let menuCornerRadius: CGFloat = 8
    
    private let snapshot: UIView
    private let frame: CGRect
    private let cellViewModel: MessageViewModel
    private let actions: [Action]
    private let dismiss: () -> Void
    
    // MARK: - UI
    
    private lazy var blurView: UIVisualEffectView = UIVisualEffectView(effect: nil)
    
    private lazy var emojiBar: UIView = {
        let result = UIView()
        result.layer.shadowColor = UIColor.black.cgColor
        result.layer.shadowOffset = CGSize.zero
        result.layer.shadowOpacity = 0.4
        result.layer.shadowRadius = 4
        result.set(.height, to: ContextMenuVC.actionViewHeight)
        
        return result
    }()
    
    private lazy var emojiPlusButton: EmojiPlusButton = {
        let result = EmojiPlusButton(
            action: self.actions.first(where: { $0.isEmojiPlus }),
            dismiss: snDismiss
        )
        result.set(.width, to: EmojiPlusButton.size)
        result.set(.height, to: EmojiPlusButton.size)
        result.layer.cornerRadius = EmojiPlusButton.size / 2
        result.layer.masksToBounds = true
        
        return result
    }()

    private lazy var menuView: UIView = {
        let result: UIView = UIView()
        result.layer.shadowColor = UIColor.black.cgColor
        result.layer.shadowOffset = CGSize.zero
        result.layer.shadowOpacity = 0.4
        result.layer.shadowRadius = 4
        
        return result
    }()
    
    private lazy var timestampLabel: UILabel = {
        let result: UILabel = UILabel()
        result.font = .systemFont(ofSize: Values.verySmallFontSize)
        result.textColor = (isLightMode ? .black : .white)
        
        if let dateForUI: Date = cellViewModel.dateForUI {
            result.text = dateForUI.formattedForDisplay
        }
        
        return result
    }()

    // MARK: - Initialization
    
    init(
        snapshot: UIView,
        frame: CGRect,
        cellViewModel: MessageViewModel,
        actions: [Action],
        dismiss: @escaping () -> Void
    ) {
        self.snapshot = snapshot
        self.frame = frame
        self.cellViewModel = cellViewModel
        self.actions = actions
        self.dismiss = dismiss
        
        super.init(nibName: nil, bundle: nil)
    }

    override init(nibName: String?, bundle: Bundle?) {
        preconditionFailure("Use init(snapshot:) instead.")
    }

    required init?(coder: NSCoder) {
        preconditionFailure("Use init(coder:) instead.")
    }
    
    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Background color
        view.backgroundColor = .clear
        
        // Blur
        view.addSubview(blurView)
        blurView.pin(to: view)
        
        // Snapshot
        snapshot.layer.shadowColor = UIColor.black.cgColor
        snapshot.layer.shadowOffset = CGSize.zero
        snapshot.layer.shadowOpacity = 0.4
        snapshot.layer.shadowRadius = 4
        view.addSubview(snapshot)
        
        // Timestamp
        view.addSubview(timestampLabel)
        timestampLabel.center(.vertical, in: snapshot)
        
        if cellViewModel.variant == .standardOutgoing {
            timestampLabel.pin(.right, to: .left, of: snapshot, withInset: -Values.smallSpacing)
        }
        else {
            timestampLabel.pin(.left, to: .right, of: snapshot, withInset: Values.smallSpacing)
        }
        
        // Emoji reacts
        let emojiBarBackgroundView = UIView()
        emojiBarBackgroundView.backgroundColor = Colors.receivedMessageBackground
        emojiBarBackgroundView.layer.cornerRadius = ContextMenuVC.actionViewHeight / 2
        emojiBarBackgroundView.layer.masksToBounds = true
        emojiBar.addSubview(emojiBarBackgroundView)
        emojiBarBackgroundView.pin(to: emojiBar)
        
        emojiBar.addSubview(emojiPlusButton)
        emojiPlusButton.pin(.right, to: .right, of: emojiBar, withInset: -Values.smallSpacing)
        emojiPlusButton.center(.vertical, in: emojiBar)
        
        let emojiBarStackView = UIStackView(
            arrangedSubviews: actions
                .filter { $0.isEmojiAction }
                .map { action -> EmojiReactsView in EmojiReactsView(for: action, dismiss: snDismiss) }
        )
        emojiBarStackView.axis = .horizontal
        emojiBarStackView.spacing = Values.smallSpacing
        emojiBarStackView.layoutMargins = UIEdgeInsets(top: 0, left: Values.smallSpacing, bottom: 0, right: Values.smallSpacing)
        emojiBarStackView.isLayoutMarginsRelativeArrangement = true
        emojiBar.addSubview(emojiBarStackView)
        emojiBarStackView.pin([ UIView.HorizontalEdge.left, UIView.VerticalEdge.top, UIView.VerticalEdge.bottom ], to: emojiBar)
        emojiBarStackView.pin(.right, to: .left, of: emojiPlusButton)
        
        // Hide the emoji bar if we have no emoji actions
        emojiBar.isHidden = emojiBarStackView.arrangedSubviews.isEmpty
        view.addSubview(emojiBar)
        
        // Menu
        let menuBackgroundView = UIView()
        menuBackgroundView.backgroundColor = Colors.receivedMessageBackground
        menuBackgroundView.layer.cornerRadius = ContextMenuVC.menuCornerRadius
        menuBackgroundView.layer.masksToBounds = true
        menuView.addSubview(menuBackgroundView)
        menuBackgroundView.pin(to: menuView)
        
        let menuStackView = UIStackView(
            arrangedSubviews: actions
                .filter { !$0.isEmojiAction && !$0.isEmojiPlus && !$0.isDismissAction }
                .map { action -> ActionView in ActionView(for: action, dismiss: snDismiss) }
        )
        menuStackView.axis = .vertical
        menuView.addSubview(menuStackView)
        menuStackView.pin(to: menuView)
        view.addSubview(menuView)
        
        // Constrains
        let menuHeight: CGFloat = CGFloat(menuStackView.arrangedSubviews.count) * ContextMenuVC.actionViewHeight
        let spacing: CGFloat = Values.smallSpacing
        let targetFrame: CGRect = calculateFrame(menuHeight: menuHeight, spacing: spacing)
        
        snapshot.pin(.left, to: .left, of: view, withInset: targetFrame.origin.x)
        snapshot.pin(.top, to: .top, of: view, withInset: targetFrame.origin.y)
        snapshot.set(.width, to: targetFrame.width)
        snapshot.set(.height, to: targetFrame.height)
        emojiBar.pin(.bottom, to: .top, of: snapshot, withInset: -spacing)
        menuView.pin(.top, to: .bottom, of: snapshot, withInset: spacing)
        
        switch cellViewModel.variant {
            case .standardOutgoing:
                menuView.pin(.right, to: .right, of: snapshot)
                emojiBar.pin(.right, to: .right, of: snapshot)
                
            case .standardIncoming:
                menuView.pin(.left, to: .left, of: snapshot)
                emojiBar.pin(.left, to: .left, of: snapshot)
                
            default: break // Should never occur
        }
        
        // Tap gesture
        let mainTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        view.addGestureRecognizer(mainTapGestureRecognizer)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        UIView.animate(withDuration: 0.25) {
            self.blurView.effect = UIBlurEffect(style: .regular)
            self.menuView.alpha = 1
        }
    }
    
    func calculateFrame(menuHeight: CGFloat, spacing: CGFloat) -> CGRect {
        var finalFrame: CGRect = frame
        let ratio: CGFloat = (frame.width / frame.height)
        
        // FIXME: Need to update this when an appropriate replacement is added (see https://teng.pub/technical/2021/11/9/uiapplication-key-window-replacement)
        let topMargin = max(UIApplication.shared.keyWindow!.safeAreaInsets.top, Values.mediumSpacing)
        let bottomMargin = max(UIApplication.shared.keyWindow!.safeAreaInsets.bottom, Values.mediumSpacing)
        let diffY = finalFrame.height + menuHeight + Self.actionViewHeight + 2 * spacing + topMargin + bottomMargin - UIScreen.main.bounds.height
        
        if diffY > 0 {
            // The screenshot needs to be shrinked. Menu + emoji bar + screenshot will fill the entire screen.
            finalFrame.size.height -= diffY
            let newWidth = ratio * finalFrame.size.height
            if cellViewModel.variant == .standardOutgoing {
                finalFrame.origin.x += finalFrame.size.width - newWidth
            }
            finalFrame.size.width = newWidth
            finalFrame.origin.y = UIScreen.main.bounds.height - finalFrame.size.height - menuHeight - bottomMargin - spacing
        }
        else {
            // The screenshot does NOT need to be shrinked.
            if finalFrame.origin.y - Self.actionViewHeight - spacing < topMargin {
                // Needs to move down
                finalFrame.origin.y = topMargin + Self.actionViewHeight + spacing
            }
            if finalFrame.origin.y + finalFrame.size.height + spacing + menuHeight + bottomMargin > UIScreen.main.bounds.height {
                // Needs to move up
                finalFrame.origin.y = UIScreen.main.bounds.height - bottomMargin - menuHeight - spacing - finalFrame.size.height
            }
        }
        
        return finalFrame
    }

    // MARK: - Layout
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        menuView.layer.shadowPath = UIBezierPath(
            roundedRect: menuView.bounds,
            cornerRadius: ContextMenuVC.menuCornerRadius
        ).cgPath
        emojiBar.layer.shadowPath = UIBezierPath(
            roundedRect: emojiBar.bounds,
            cornerRadius: (ContextMenuVC.actionViewHeight / 2)
        ).cgPath
    }

    // MARK: - Interaction
    
    @objc private func handleTap() {
        snDismiss()
    }
    
    func snDismiss() {
        UIView.animate(
            withDuration: 0.25,
            animations: { [weak self] in
                self?.blurView.effect = nil
                self?.menuView.alpha = 0
                self?.emojiBar.alpha = 0
                self?.snapshot.alpha = 0
                self?.timestampLabel.alpha = 0
            },
            completion: { [weak self] _ in
                self?.dismiss()
                self?.actions.first(where: { $0.isDismissAction })?.work()
            }
        )
    }
}
