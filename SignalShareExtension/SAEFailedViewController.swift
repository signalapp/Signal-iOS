//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import PureLayout
import SignalServiceKit
import SignalUI

// All Observer methods will be invoked from the main thread.
protocol SAEFailedViewDelegate: AnyObject {
    func shareViewWasCancelled()
}

final class SAEFailedViewController: UIViewController {

    weak var delegate: SAEFailedViewDelegate?

    let failureTitle: String
    let failureMessage: String

    // MARK: Initializers and Factory Methods

    init(delegate: SAEFailedViewDelegate, title: String, message: String) {
        self.delegate = delegate
        self.failureTitle = title
        self.failureMessage = message
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable, message: "use other constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        super.loadView()

        self.navigationItem.leftBarButtonItem = .cancelButton { [weak self] in
            self?.cancelPressed()
        }
        self.navigationItem.title = "Signal"

        self.view.backgroundColor = Theme.launchScreenBackgroundColor

        let logoImage = UIImage(named: "signal-logo-128-launch-screen")
        let logoImageView = UIImageView(image: logoImage)
        self.view.addSubview(logoImageView)
        logoImageView.autoCenterInSuperview()
        let logoSize = CGFloat(120)
        logoImageView.autoSetDimension(.width, toSize: logoSize)
        logoImageView.autoSetDimension(.height, toSize: logoSize)

        let titleLabel = UILabel()
        titleLabel.textColor = UIColor.white
        titleLabel.font = .semiboldFont(ofSize: 18)
        titleLabel.text = failureTitle
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        self.view.addSubview(titleLabel)
        titleLabel.autoPinEdge(toSuperviewEdge: .leading, withInset: 20)
        titleLabel.autoPinEdge(toSuperviewEdge: .trailing, withInset: 20)
        titleLabel.autoPinEdge(.top, to: .bottom, of: logoImageView, withOffset: 25)

        let messageLabel = UILabel()
        messageLabel.textColor = UIColor.white
        messageLabel.font = .regularFont(ofSize: 14)
        messageLabel.text = failureMessage
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        self.view.addSubview(messageLabel)
        messageLabel.autoPinEdge(toSuperviewEdge: .leading, withInset: 20)
        messageLabel.autoPinEdge(toSuperviewEdge: .trailing, withInset: 20)
        messageLabel.autoPinEdge(.top, to: .bottom, of: titleLabel, withOffset: 10)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.navigationController?.isNavigationBarHidden = false
    }

    // MARK: - Event Handlers

    private func cancelPressed() {
        guard let delegate = delegate else {
            owsFailDebug("missing delegate")
            return
        }
        delegate.shareViewWasCancelled()
    }
}
