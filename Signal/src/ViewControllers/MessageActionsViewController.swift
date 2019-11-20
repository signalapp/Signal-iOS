//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class MessageAction: NSObject {
    let block: (MessageAction) -> Void
    let image: UIImage
    let accessibilityIdentifier: String

    public init(image: UIImage,
                accessibilityIdentifier: String,
                block: @escaping (MessageAction) -> Void) {
        self.image = image
        self.accessibilityIdentifier = accessibilityIdentifier
        self.block = block
    }
}

@objc
protocol MessageActionsViewControllerDelegate: class {
    func messageActionsViewControllerDidDismiss(_ messageActionsViewController: MessageActionsViewController, withAction: MessageAction?)
}

@objc
class MessageActionsViewController: UIViewController {
    @objc
    let focusedInteraction: TSInteraction
    @objc
    let focusedView: UIView
    private let actionsToolbar: MessageActionsToolbar

    @objc
    let bottomBar = UIView()

    @objc
    let backdropView = UIView()

    @objc
    public weak var delegate: MessageActionsViewControllerDelegate?

    @objc
    init(focusedInteraction: TSInteraction, focusedView: UIView, actions: [MessageAction]) {
        self.focusedInteraction = focusedInteraction
        self.focusedView = focusedView
        self.actionsToolbar = MessageActionsToolbar(actions: actions)

        super.init(nibName: nil, bundle: nil)

        self.actionsToolbar.actionDelegate = self
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = UIView()

        let alpha: CGFloat = Theme.isDarkThemeEnabled ? 0.4 : 0.2
        backdropView.backgroundColor = UIColor.black.withAlphaComponent(alpha)

        view.addSubview(backdropView)
        backdropView.autoPinEdgesToSuperviewEdges()

        bottomBar.backgroundColor = Theme.toolbarBackgroundColor
        view.addSubview(bottomBar)
        bottomBar.autoPinWidthToSuperview()

        bottomBar.addSubview(actionsToolbar)
        actionsToolbar.autoPinWidthToSuperview()
        actionsToolbar.autoPinEdge(toSuperviewEdge: .top)
        actionsToolbar.autoPinEdge(toSuperviewSafeArea: .bottom)

        backdropView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapBackdrop)))
    }

    private var snapshotFocusedView: UIView?
    private func addSnapshotFocusedView() {
        snapshotFocusedView?.removeFromSuperview()
        snapshotFocusedView = nil

        guard let snapshotView = focusedView.snapshotView(afterScreenUpdates: false) else {
            return owsFailDebug("snapshotView was unexpectedly nil")
        }
        view.addSubview(snapshotView)

        guard let focusedViewSuperview = focusedView.superview else {
            return owsFailDebug("focusedViewSuperview was unexpectedly nil")
        }

        let convertedFrame = view.convert(focusedView.frame, from: focusedViewSuperview)
        snapshotView.frame = convertedFrame
        snapshotView.isUserInteractionEnabled = false

        snapshotFocusedView = snapshotView
    }

    @objc func didTapBackdrop() {
        delegate?.messageActionsViewControllerDidDismiss(self, withAction: nil)
    }

    @objc(presentOnWindow:prepareConstraints:animateAlongside:completion:)
    func present(
        on window: UIWindow,
        prepareConstraints: () -> Void,
        animateAlongside: (() -> Void)?,
        completion: (() -> Void)?
    ) {
        guard view.superview == nil else {
            return owsFailDebug("trying to dismiss when already presented")
        }

        window.addSubview(view)
        prepareConstraints()

        backdropView.alpha = 0
        bottomBar.alpha = 0

        window.layoutIfNeeded()

        addSnapshotFocusedView()

        UIView.animate(withDuration: 0.15, animations: {
            self.backdropView.alpha = 1
            self.bottomBar.alpha = 1
            animateAlongside?()
        }) { _ in
            completion?()
        }
    }

    @objc(dismissAndAnimateAlongside:completion:)
    func dismiss(animateAlongside: (() -> Void)?, completion: (() -> Void)?) {
        guard view.superview != nil else {
            return owsFailDebug("trying to dismiss when not presented")
        }

        UIView.animate(withDuration: 0.15, animations: {
            self.backdropView.alpha = 0
            self.bottomBar.alpha = 0
            self.snapshotFocusedView?.alpha = 0
            animateAlongside?()
        }) { _ in
            self.view.removeFromSuperview()
            completion?()
        }
    }
}

extension MessageActionsViewController: MessageActionsToolbarDelegate {
    fileprivate func messageActionsToolbar(_ messageActionsToolbar: MessageActionsToolbar, executedAction: MessageAction) {
        delegate?.messageActionsViewControllerDidDismiss(self, withAction: executedAction)
    }
}

private protocol MessageActionsToolbarDelegate: class {
    func messageActionsToolbar(_ messageActionsToolbar: MessageActionsToolbar, executedAction: MessageAction)
}

private class MessageActionsToolbar: UIToolbar {

    weak var actionDelegate: MessageActionsToolbarDelegate?

    let actions: [MessageAction]

    deinit {
        Logger.verbose("")
    }

    required init(actions: [MessageAction]) {
        self.actions = actions

        super.init(frame: .zero)

        isTranslucent = false
        isOpaque = true

        autoresizingMask = .flexibleHeight
        translatesAutoresizingMaskIntoConstraints = false
        barTintColor = Theme.toolbarBackgroundColor
        setShadowImage(UIImage(), forToolbarPosition: .any)

        buildItems()
    }

    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: -

    private var itemToAction = [UIBarButtonItem: MessageAction]()
    private func buildItems() {
        var newItems = [UIBarButtonItem]()

        for action in actions {
            let actionItem = UIBarButtonItem(
                image: action.image.withRenderingMode(.alwaysTemplate),
                style: .plain,
                target: self,
                action: #selector(didTapItem(_:))
            )
            actionItem.tintColor = Theme.primaryIconColor
            newItems.append(actionItem)
            itemToAction[actionItem] = action

            if action != actions.last {
                newItems.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
            }
        }
        items = newItems
    }

    @objc func didTapItem(_ item: UIBarButtonItem) {
        guard let action = itemToAction[item] else {
            return owsFailDebug("missing action for item")
        }

        actionDelegate?.messageActionsToolbar(self, executedAction: action)
        action.block(action)
    }
}
