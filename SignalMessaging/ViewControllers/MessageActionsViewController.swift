//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class MessageActionsViewController: UIViewController {

    @objc
    weak var delegate: MessageActionsDelegate?

    override func loadView() {
        self.view = UIView()
        view.backgroundColor = .purple

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTapBackground))
        self.view.addGestureRecognizer(tapGesture)
    }

    @objc
    func didTapBackground() {
        self.delegate?.dismissMessageActions(self)
    }
}
