//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import PureLayout
import SignalServiceKit
import SignalUI

class LinkAndSyncLoadingViewController: UIViewController {

    var activityIndicator: UIActivityIndicatorView!
    var progressView: UIProgressView!

    var percentCompleted: Float? {
        didSet {
            guard progressView != nil else {
                return
            }

            updateProgressViewVisability()
            progressView.setProgress(percentCompleted ?? 0, animated: true)
        }
    }

    func updateProgressViewVisability() {
        guard progressView != nil, activityIndicator != nil else {
            return
        }

        // Prefer to show progress view when progress is present
        if (self.percentCompleted ?? 0) == 0 {
            activityIndicator.startAnimating()
            self.progressView.isHidden = true
            self.activityIndicator.isHidden = false
        } else {
            activityIndicator.stopAnimating()
            self.progressView.isHidden = false
            self.activityIndicator.isHidden = true
        }
    }

    // MARK: Initializers and Factory Methods

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable, message: "use other constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        super.loadView()

        self.view.backgroundColor = Theme.backgroundColor

        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.color = Theme.primaryIconColor
        self.activityIndicator = activityIndicator
        self.view.addSubview(activityIndicator)
        activityIndicator.autoCenterInSuperview()

        progressView = UIProgressView(progressViewStyle: .default)
        progressView.setProgress(percentCompleted ?? 0, animated: false)

        self.view.addSubview(progressView)
        progressView.autoVCenterInSuperview()
        progressView.autoPinWidthToSuperview(withMargin: .scaleFromIPhone5(30))
        progressView.progressTintColor = Theme.accentBlueColor

        updateProgressViewVisability()

        let label = UILabel()
        label.textColor = Theme.primaryTextColor
        label.font = .systemFont(ofSize: 17)
        label.text = OWSLocalizedString(
            "LINKING_SYNCING_MESSAGES_TITLE",
            value: "Syncing messages",
            comment: "Title shown when loading messages during linking process"
        )
        self.view.addSubview(label)
        label.autoHCenterInSuperview()
        label.autoPinEdge(.top, to: .bottom, of: activityIndicator, withOffset: 12)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.navigationController?.isNavigationBarHidden = false
    }
}
