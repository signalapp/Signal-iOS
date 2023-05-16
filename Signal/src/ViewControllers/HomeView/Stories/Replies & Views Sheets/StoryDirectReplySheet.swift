//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalServiceKit

public class StoryDirectReplySheet: OWSViewController, StoryReplySheet {

    var dismissHandler: (() -> Void)?

    var bottomBar: UIView { inputToolbar }
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

    let backdropView: UIView? = UIView()

    init(storyMessage: StoryMessage) {
        self.storyMessage = storyMessage
        super.init()
        modalPresentationStyle = .custom
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        inputToolbar.becomeFirstResponder()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        inputToolbar.resignFirstResponder()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tapGesture)

        view.addSubview(inputToolbar)
        inputToolbar.autoPinWidthToSuperview()
        inputToolbar.autoPin(toTopLayoutGuideOf: self, withInset: 0, relation: .greaterThanOrEqual)
        inputToolbar.autoPinEdge(.bottom, to: .bottom, of: keyboardLayoutGuideViewSafeArea)
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
