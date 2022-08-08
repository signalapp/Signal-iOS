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
        
        snapshot.pin(.left, to: .left, of: view, withInset: frame.origin.x)
        snapshot.pin(.top, to: .top, of: view, withInset: frame.origin.y)
        snapshot.set(.width, to: frame.width)
        snapshot.set(.height, to: frame.height)
        
        // Timestamp
        view.addSubview(timestampLabel)
        timestampLabel.center(.vertical, in: snapshot)
        
        if cellViewModel.variant == .standardOutgoing {
            timestampLabel.pin(.right, to: .left, of: snapshot, withInset: -Values.smallSpacing)
        }
        else {
            timestampLabel.pin(.left, to: .right, of: snapshot, withInset: Values.smallSpacing)
        }
        
        // Menu
        let menuBackgroundView = UIView()
        menuBackgroundView.backgroundColor = Colors.receivedMessageBackground
        menuBackgroundView.layer.cornerRadius = ContextMenuVC.menuCornerRadius
        menuBackgroundView.layer.masksToBounds = true
        menuView.addSubview(menuBackgroundView)
        menuBackgroundView.pin(to: menuView)
        
        let menuStackView = UIStackView(
            arrangedSubviews: actions
                .filter { !$0.isDismissAction }
                .map { action -> ActionView in ActionView(for: action, dismiss: snDismiss) }
        )
        menuStackView.axis = .vertical
        menuView.addSubview(menuStackView)
        menuStackView.pin(to: menuView)
        view.addSubview(menuView)
        
        let menuHeight = (CGFloat(actions.count) * ContextMenuVC.actionViewHeight)
        let spacing = Values.smallSpacing
        // FIXME: Need to update this when an appropriate replacement is added (see https://teng.pub/technical/2021/11/9/uiapplication-key-window-replacement)
        let margin = max(UIApplication.shared.keyWindow!.safeAreaInsets.bottom, Values.mediumSpacing)
        
        if frame.maxY + spacing + menuHeight > UIScreen.main.bounds.height - margin {
            menuView.pin(.bottom, to: .top, of: snapshot, withInset: -spacing)
        }
        else {
            menuView.pin(.top, to: .bottom, of: snapshot, withInset: spacing)
        }

        switch cellViewModel.variant {
            case .standardOutgoing: menuView.pin(.right, to: .right, of: snapshot)
            case .standardIncoming: menuView.pin(.left, to: .left, of: snapshot)
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

    // MARK: - Layout
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        menuView.layer.shadowPath = UIBezierPath(
            roundedRect: menuView.bounds,
            cornerRadius: ContextMenuVC.menuCornerRadius
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
