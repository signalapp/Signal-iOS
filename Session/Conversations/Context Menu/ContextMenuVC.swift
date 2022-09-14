// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionMessagingKit

final class ContextMenuVC: UIViewController {
    private static let actionViewHeight: CGFloat = 40
    private static let menuCornerRadius: CGFloat = 8
    
    private let snapshot: UIView
    private let frame: CGRect
    private var targetFrame: CGRect = .zero
    private let cellViewModel: MessageViewModel
    private let actions: [Action]
    private let dismiss: () -> Void
    
    // MARK: - UI
    
    private lazy var blurView: UIVisualEffectView = UIVisualEffectView(effect: nil)
    
    private lazy var emojiBar: UIView = {
        let result: UIView = UIView()
        result.themeShadowColor = .black
        result.layer.shadowOffset = CGSize.zero
        result.layer.shadowOpacity = 0.4
        result.layer.shadowRadius = 4
        result.set(.height, to: ContextMenuVC.actionViewHeight)
        
        return result
    }()
    
    private lazy var emojiPlusButton: EmojiPlusButton = {
        let result: EmojiPlusButton = EmojiPlusButton(
            action: self.actions.first(where: { $0.isEmojiPlus }),
            dismiss: snDismiss
        )
        result.clipsToBounds = true
        result.set(.width, to: EmojiPlusButton.size)
        result.set(.height, to: EmojiPlusButton.size)
        result.layer.cornerRadius = (EmojiPlusButton.size / 2)
        
        return result
    }()

    private lazy var menuView: UIView = {
        let result: UIView = UIView()
        result.themeShadowColor = .black
        result.layer.shadowOffset = CGSize.zero
        result.layer.shadowOpacity = 0.4
        result.layer.shadowRadius = 4
        
        return result
    }()
    
    private lazy var timestampLabel: UILabel = {
        let result: UILabel = UILabel()
        result.font = .systemFont(ofSize: Values.verySmallFontSize)
        result.text = cellViewModel.dateForUI.formattedForDisplay
        result.themeTextColor = .textPrimary
        
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
        view.themeBackgroundColor = .clear
        
        // Blur
        view.addSubview(blurView)
        blurView.pin(to: view)
        
        // Snapshot
        snapshot.themeShadowColor = .black
        snapshot.layer.shadowOffset = CGSize.zero
        snapshot.layer.shadowOpacity = 0.4
        snapshot.layer.shadowRadius = 4
        view.addSubview(snapshot)
        
        // Emoji reacts
        let emojiBarBackgroundView: UIView = UIView()
        emojiBarBackgroundView.clipsToBounds = true
        emojiBarBackgroundView.themeBackgroundColor = .reactions_contextBackground
        emojiBarBackgroundView.layer.cornerRadius = (ContextMenuVC.actionViewHeight / 2)
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
        let menuBackgroundView: UIView = UIView()
        menuBackgroundView.clipsToBounds = true
        menuBackgroundView.themeBackgroundColor = .contextMenu_background
        menuBackgroundView.layer.cornerRadius = ContextMenuVC.menuCornerRadius
        menuView.addSubview(menuBackgroundView)
        menuBackgroundView.pin(to: menuView)
        
        let menuStackView = UIStackView(
            arrangedSubviews: actions
                .filter { !$0.isEmojiAction && !$0.isEmojiPlus && !$0.isDismissAction }
                .map { action -> ActionView in ActionView(for: action, dismiss: snDismiss) }
        )
        menuStackView.axis = .vertical
        menuBackgroundView.addSubview(menuStackView)
        menuStackView.pin(to: menuBackgroundView)
        view.addSubview(menuView)
        
        // Timestamp
        view.addSubview(timestampLabel)
        timestampLabel.pin(.top, to: .top, of: menuView)
        timestampLabel.set(.height, to: ContextMenuVC.actionViewHeight)
        
        if cellViewModel.variant == .standardOutgoing {
            timestampLabel.pin(.right, to: .left, of: menuView, withInset: -Values.mediumSpacing)
        }
        else {
            timestampLabel.pin(.left, to: .right, of: menuView, withInset: Values.mediumSpacing)
        }
        
        // Constrains
        let menuHeight: CGFloat = CGFloat(menuStackView.arrangedSubviews.count) * ContextMenuVC.actionViewHeight
        let spacing: CGFloat = Values.smallSpacing
        self.targetFrame = calculateFrame(menuHeight: menuHeight, spacing: spacing)
        
        // Position the snapshot view in it's original message position
        snapshot.frame = self.frame
        emojiBar.pin(.bottom, to: .top, of: view, withInset: targetFrame.minY - spacing)
        menuView.pin(.top, to: .top, of: view, withInset: targetFrame.maxY + spacing)
        
        switch cellViewModel.variant {
            case .standardOutgoing:
                menuView.pin(.right, to: .right, of: view, withInset: -(UIScreen.main.bounds.width - targetFrame.maxX))
                emojiBar.pin(.right, to: .right, of: view, withInset: -(UIScreen.main.bounds.width - targetFrame.maxX))
            
            case .standardIncoming:
                menuView.pin(.left, to: .left, of: view, withInset: targetFrame.minX)
                emojiBar.pin(.left, to: .left, of: view, withInset: targetFrame.minX)
                
            default: break // Should never occur
        }
        
        // Tap gesture
        let mainTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        view.addGestureRecognizer(mainTapGestureRecognizer)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Fade the menus in and animate the snapshot from it's starting position to where it
        // needs to be on screen in order to fit the menu
        let view: UIView = self.view
        let targetFrame: CGRect = self.targetFrame
        
        UIView.animate(withDuration: 0.3) { [weak self] in
            self?.blurView.effect = UIBlurEffect(style: .regular)
            self?.menuView.alpha = 1
        }
        
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0.6,
            options: .curveEaseInOut,
            animations: { [weak self] in
                self?.snapshot.pin(.left, to: .left, of: view, withInset: targetFrame.origin.x)
                self?.snapshot.pin(.top, to: .top, of: view, withInset: targetFrame.origin.y)
                self?.snapshot.set(.width, to: targetFrame.width)
                self?.snapshot.set(.height, to: targetFrame.height)
                self?.snapshot.superview?.setNeedsLayout()
                self?.snapshot.superview?.layoutIfNeeded()
            },
            completion: nil
        )
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
        let currentFrame: CGRect = self.snapshot.frame
        let originalFrame: CGRect = self.frame
        
        // Remove the snapshot view from the view hierarchy to remove its constaints (and prevent
        // them from causing animation bugs - also need to turn 'translatesAutoresizingMaskIntoConstraints'
        // back on so autod layout doesn't mess with the frame manipulation)
        let oldSuperview: UIView? = self.snapshot.superview
        self.snapshot.removeFromSuperview()
        oldSuperview?.insertSubview(self.snapshot, aboveSubview: self.blurView)
        
        self.snapshot.translatesAutoresizingMaskIntoConstraints = true
        self.snapshot.frame = currentFrame
        
        UIView.animate(
            withDuration: 0.15,
            delay: 0,
            options: .curveEaseOut,
            animations: { [weak self] in
                self?.snapshot.frame = originalFrame
            },
            completion: nil
        )
        
        UIView.animate(
            withDuration: 0.25,
            animations: { [weak self] in
                self?.blurView.effect = nil
                self?.menuView.alpha = 0
                self?.emojiBar.alpha = 0
                self?.timestampLabel.alpha = 0
            },
            completion: { [weak self] _ in
                self?.dismiss()
                self?.actions.first(where: { $0.isDismissAction })?.work()
            }
        )
    }
}
