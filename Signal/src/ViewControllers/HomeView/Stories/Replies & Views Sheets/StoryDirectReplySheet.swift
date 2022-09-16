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
    weak var interactiveTransitionCoordinator: StoryInteractiveTransitionCoordinator?

    var reactionPickerBackdrop: UIView?
    var reactionPicker: MessageReactionPicker?

    let backdropView: UIView? = UIView()

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

extension StoryDirectReplySheet: UIViewControllerTransitioningDelegate {
    public func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        return StoryReplySheetAnimator(
            isPresenting: true,
            isInteractive: interactiveTransitionCoordinator != nil,
            backdropView: backdropView
        )
    }

    public func animationController(
        forDismissed dismissed: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        return StoryReplySheetAnimator(
            isPresenting: false,
            isInteractive: false,
            backdropView: backdropView
        )
    }

    public func interactionControllerForPresentation(
        using animator: UIViewControllerAnimatedTransitioning
    ) -> UIViewControllerInteractiveTransitioning? {
        interactiveTransitionCoordinator?.mode = .reply
        return interactiveTransitionCoordinator
    }
}
