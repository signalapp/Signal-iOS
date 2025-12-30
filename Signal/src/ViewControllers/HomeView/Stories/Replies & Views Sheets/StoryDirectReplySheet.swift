//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import SignalUI

public class StoryDirectReplySheet: OWSViewController, StoryReplySheet {

    var dismissHandler: (() -> Void)?

    var bottomBar: UIView { inputToolbar }
    lazy var inputToolbar: StoryReplyInputToolbar = {
        let quotedReplyModel = SSKEnvironment.shared.databaseStorageRef.read {
            QuotedReplyModel.build(replyingTo: storyMessage, transaction: $0)
        }
        let toolbar = StoryReplyInputToolbar(isGroupStory: false, quotedReplyModel: quotedReplyModel, spoilerState: spoilerState)
        toolbar.delegate = self
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        return toolbar
    }()

    let storyMessage: StoryMessage
    lazy var thread: TSThread? = SSKEnvironment.shared.databaseStorageRef.read { storyMessage.context.thread(transaction: $0) }

    let spoilerState: SpoilerRenderState

    private var inputToolbarBottomConstraint: NSLayoutConstraint?

    init(storyMessage: StoryMessage, spoilerState: SpoilerRenderState) {
        self.storyMessage = storyMessage
        self.spoilerState = spoilerState
        super.init()
        modalPresentationStyle = .custom
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        inputToolbar.becomeFirstResponder()
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        inputToolbar.resignFirstResponder()
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tapGesture)

        let inputToolbarBottomConstraint = inputToolbar.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor)
        view.addSubview(inputToolbar)
        NSLayoutConstraint.activate([
            inputToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputToolbarBottomConstraint,
            inputToolbar.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
        ])
        self.inputToolbarBottomConstraint = inputToolbarBottomConstraint
    }

    @objc
    func handleTap(_ tap: UITapGestureRecognizer) {
        guard !inputToolbar.bounds.contains(tap.location(in: inputToolbar)) else { return }
        dismiss(animated: true)
    }

    override public func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        // We don't want `inputToolbar` to stay attached to the keyboard's layout guide during dismiss animation
        // as this creates unpleasant animations where the bar flies across the screen.
        // To workaround that we freeze vertical position of the `inputToolbar`
        // just before the animation stars to that the bar is animated with the whole view.
        if let inputToolbarBottomConstraint {
            let fixedPositionConstraint = inputToolbar.topAnchor.constraint(
                equalTo: view.topAnchor,
                constant: inputToolbar.frame.y,
            )

            NSLayoutConstraint.deactivate([inputToolbarBottomConstraint])
            NSLayoutConstraint.activate([fixedPositionConstraint])

            self.inputToolbarBottomConstraint = nil
        }
        super.dismiss(animated: flag) { [dismissHandler] in
            completion?()
            dismissHandler?()
        }
    }

    func didSendMessage() {
        dismiss(animated: true)
    }
}
