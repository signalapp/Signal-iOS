//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

// All Observer methods will be invoked from the main thread.
protocol SAEFailedViewDelegate: AnyObject {
    func shareViewWasCancelled()
}

class SAEFailedViewController: UIViewController {

    private weak var delegate: SAEFailedViewDelegate?

    private let failureTitle: String
    private let failureMessage: String

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

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.leftBarButtonItem = .cancelButton { [weak self] in
            self?.cancelPressed()
        }
        navigationItem.title = "Signal"

        view.backgroundColor = .Signal.background

        let logoImageView = UIImageView(image: UIImage(named: "signal-logo-128-launch-screen"))

        let titleLabel = UILabel.headlineLabel(text: failureTitle, semibold: true)
        titleLabel.text = failureTitle
        titleLabel.textAlignment = .center

        let messageLabel = UILabel.subheadlineLabel(text: failureMessage)
        messageLabel.textAlignment = .center

        let vStack = UIStackView(arrangedSubviews: [logoImageView, titleLabel, messageLabel])
        vStack.alignment = .center
        vStack.axis = .vertical
        vStack.spacing = 12
        vStack.setCustomSpacing(24, after: logoImageView)
        view.addSubview(vStack)

        vStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.topAnchor),
            vStack.centerYAnchor.constraint(equalTo: view.layoutMarginsGuide.centerYAnchor),

            vStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),
            vStack.centerXAnchor.constraint(equalTo: view.layoutMarginsGuide.centerXAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.isNavigationBarHidden = false
    }

    // MARK: - Event Handlers

    private func cancelPressed() {
        guard let delegate else {
            owsFailDebug("missing delegate")
            return
        }
        delegate.shareViewWasCancelled()
    }
}
