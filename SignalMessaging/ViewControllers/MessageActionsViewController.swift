//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
protocol MessageActionsDelegate: class {
    func messageActionsDidHide(_ messageActionsViewController: MessageActionsViewController)
}

@objc
class MessageActionsViewController: UIViewController {

    @objc
    weak var delegate: MessageActionsDelegate?

    let focusedView: UIView

    @objc
    required init(focusedView: UIView) {
        self.focusedView = focusedView

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        self.view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)

        highlightFocusedView()

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTapBackground))
        self.view.addGestureRecognizer(tapGesture)
    }

    private func highlightFocusedView() {
        guard let snapshotView = self.focusedView.snapshotView(afterScreenUpdates: false) else {
            owsFail("\(self.logTag) in \(#function) snapshotView was unexpectedly nil")
            return
        }
        view.addSubview(snapshotView)

        guard let focusedViewSuperview = focusedView.superview else {
            owsFail("\(self.logTag) in \(#function) focusedViewSuperview was unexpectedly nil")
            return
        }

        let convertedFrame = view.convert(focusedView.frame, from: focusedViewSuperview)
        snapshotView.frame = convertedFrame
    }

    @objc
    func didTapBackground() {
        self.delegate?.messageActionsDidHide(self)
    }
}
