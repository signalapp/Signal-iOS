//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import UIKit
import SignalServiceKit

public class StoryDirectReplySheet: OWSViewController, StoryReplySheet {

    var dismissHandler: (() -> Void)?

    lazy var inputToolbar: StoryReplyInputToolbar = {
        let quotedReplyModel = databaseStorage.read {
            OWSQuotedReplyModel.quotedReply(from: storyMessage, transaction: $0)
        }
        let toolbar = StoryReplyInputToolbar(quotedReplyModel: quotedReplyModel)
        toolbar.delegate = self
        return toolbar
    }()
    let storyMessage: StoryMessage
    lazy var thread: TSThread? = databaseStorage.read { storyMessage.context.thread(transaction: $0) }

    var reactionPickerBackdrop: UIView?
    var reactionPicker: MessageReactionPicker?

    @objc
    init(storyMessage: StoryMessage) {
        self.storyMessage = storyMessage
        super.init()
        modalPresentationStyle = .custom
        transitioningDelegate = self
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        inputToolbar.textView.becomeFirstResponder()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        inputToolbar.textView.resignFirstResponder()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tapGesture)

        view.addSubview(inputToolbar)
        inputToolbar.autoPinWidthToSuperview()
        inputToolbar.autoPin(toTopLayoutGuideOf: self, withInset: 0, relation: .greaterThanOrEqual)
        autoPinView(toBottomOfViewControllerOrKeyboard: inputToolbar, avoidNotch: true)
    }

    @objc
    func handleTap(_ tap: UITapGestureRecognizer) {
        guard !inputToolbar.bounds.contains(tap.location(in: inputToolbar)) else { return }
        dismiss(animated: true)
    }

    public override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        super.dismiss(animated: flag) { [dismissHandler] in
            completion?()
            dismissHandler?()
        }
    }

    func didSendMessage() {
        dismiss(animated: true)
    }
}

// MARK: -

private class StoryDirectReplySheetPresentationController: UIPresentationController {
    let backdropView = UIView()

    override init(presentedViewController: UIViewController, presenting presentingViewController: UIViewController?) {
        super.init(presentedViewController: presentedViewController, presenting: presentingViewController)

        let alpha: CGFloat = Theme.isDarkThemeEnabled ? 0.7 : 0.6
        backdropView.backgroundColor = UIColor.black.withAlphaComponent(alpha)
    }

    override func presentationTransitionWillBegin() {
        guard let containerView = containerView else { return }

        backdropView.alpha = 0
        containerView.addSubview(backdropView)
        backdropView.autoPinEdgesToSuperviewEdges()
        containerView.layoutIfNeeded()

        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.backdropView.alpha = 1
        }, completion: nil)
    }

    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.backdropView.alpha = 0
        }, completion: { _ in
            self.backdropView.removeFromSuperview()
        })
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard let presentedView = presentedView else { return }
        coordinator.animate(alongsideTransition: { _ in
            presentedView.frame = self.frameOfPresentedViewInContainerView
            presentedView.layoutIfNeeded()
        }, completion: nil)
    }
}

extension StoryDirectReplySheet: UIViewControllerTransitioningDelegate {
    public func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        return StoryDirectReplySheetPresentationController(presentedViewController: presented, presenting: presenting)
    }
}
