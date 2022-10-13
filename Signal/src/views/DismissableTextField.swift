//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

protocol DismissInputBarDelegate: AnyObject {
    func dismissInputBarDidTapDismiss(_ dismissInputBar: DismissInputBar)
}

class DismissInputBar: UIToolbar {

    weak var dismissDelegate: DismissInputBarDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)

        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let dismissButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(didTapDone))
        dismissButton.imageInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 40)
        dismissButton.tintColor = Theme.accentBlueColor

        self.items = [spacer, dismissButton]
        self.isTranslucent = false
        self.isOpaque = true
        self.barTintColor = Theme.toolbarBackgroundColor

        self.autoresizingMask = .flexibleHeight
        self.translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    public func didTapDone() {
        self.dismissDelegate?.dismissInputBarDidTapDismiss(self)
    }
}

@objc
public class DismissableTextField: OWSTextField, DismissInputBarDelegate {

    private let dismissBar: DismissInputBar

    override init(frame: CGRect) {
        self.dismissBar = DismissInputBar()

        super.init(frame: frame)

        self.inputAccessoryView = dismissBar

        dismissBar.dismissDelegate = self
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: DismissInputBarDelegate

    func dismissInputBarDidTapDismiss(_ dismissInputBar: DismissInputBar) {
        self.resignFirstResponder()
    }
}
