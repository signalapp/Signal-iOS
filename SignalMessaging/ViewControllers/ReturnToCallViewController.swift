//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol ReturnToCallViewControllerDelegate: class {
    func returnToCallWasTapped(_ viewController: ReturnToCallViewController)
}

@objc
public class ReturnToCallViewController: UIViewController {

    public weak var delegate: ReturnToCallViewControllerDelegate?

    let returnToCallLabel = UILabel()

    public func startAnimating() {
        NotificationCenter.default.addObserver(self, selector: #selector(didTapStatusBar(notification:)), name: .TappedStatusBar, object: nil)
        self.returnToCallLabel.layer.removeAllAnimations()
        self.returnToCallLabel.alpha = 1
        UIView.animate(withDuration: 1,
                       delay: 0,
                       options: [.repeat, .autoreverse],
                       animations: { self.returnToCallLabel.alpha = 0 },
                       completion: { _ in self.returnToCallLabel.alpha = 1 })
    }

    public func stopAnimating() {
        NotificationCenter.default.removeObserver(self, name: .TappedStatusBar, object: nil)
        self.returnToCallLabel.layer.removeAllAnimations()
    }

    override public func loadView() {
        self.view = UIView()

        // This is the color of the iOS "return to call" banner.
        view.backgroundColor = UIColor(rgbHex: 0x4cd964)
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTapView))
        view.addGestureRecognizer(tapGesture)

        view.addSubview(returnToCallLabel)

        // System UI doesn't use dynamic type for status bar; neither do we.
        returnToCallLabel.font = UIFont.ows_regularFont(withSize: 14)
        returnToCallLabel.text = NSLocalizedString("CALL_WINDOW_RETURN_TO_CALL", comment: "Label for the 'return to call' banner.")
        returnToCallLabel.textColor = .white

        returnToCallLabel.autoPinEdge(toSuperviewEdge: .bottom, withInset: 2)
        returnToCallLabel.setCompressionResistanceHigh()
        returnToCallLabel.setContentHuggingHigh()
        returnToCallLabel.autoHCenterInSuperview()
    }

    @objc
    public func didTapView(gestureRecognizer: UITapGestureRecognizer) {
        self.delegate?.returnToCallWasTapped(self)
    }

    @objc
    public func didTapStatusBar(notification: Notification) {
        self.delegate?.returnToCallWasTapped(self)
    }

    override public func viewWillLayoutSubviews() {
        Logger.debug("\(self.logTag) in \(#function)")

        super.viewWillLayoutSubviews()
    }

    override public func viewDidLayoutSubviews() {
        Logger.debug("\(self.logTag) in \(#function)")

        super.viewDidLayoutSubviews()
    }
}
