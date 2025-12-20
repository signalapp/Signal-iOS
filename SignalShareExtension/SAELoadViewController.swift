//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import PureLayout
import SignalServiceKit
import SignalUI
import UIKit

class SAELoadViewController: UIViewController, OWSNavigationChildController {

    private weak var delegate: ShareViewDelegate?
    private let shouldMimicRecipientPicker: Bool

    private var activityIndicator: UIActivityIndicatorView!
    private var progressView: UIProgressView!

    var progress: Progress? {
        didSet {
            guard progressView != nil else {
                return
            }

            updateProgressViewVisibility()
            progressView.observedProgress = progress
        }
    }

    private func updateProgressViewVisibility() {
        guard progressView != nil, activityIndicator != nil else {
            return
        }

        // Prefer to show progress view when progress is present
        if self.progress == nil {
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

    init(delegate: ShareViewDelegate, shouldMimicRecipientPicker: Bool = false) {
        self.delegate = delegate
        self.shouldMimicRecipientPicker = shouldMimicRecipientPicker
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable, message: "use other constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        super.loadView()

        // It's not (currently) safe to create a SharingThreadPickerViewController
        // while the Share Extension is launching, so instead mimic the header of
        // the picker on the loading view controller.
        //
        // TODO: Make it safe to do so and remove this hack.
        if self.shouldMimicRecipientPicker {
            self.title = ConversationPickerViewController.Strings.defaultTitle
            self.navigationItem.rightBarButtonItem = .cancelButton(action: {})
            self.navigationItem.rightBarButtonItem?.isEnabled = false
        }

        self.view.backgroundColor = (
            self.shouldMimicRecipientPicker
                ? Theme.tableView2PresentedBackgroundColor
                : Theme.backgroundColor,
        )

        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.color = Theme.primaryIconColor
        self.activityIndicator = activityIndicator
        self.view.addSubview(activityIndicator)
        activityIndicator.autoCenterInSuperview()

        progressView = UIProgressView(progressViewStyle: .default)
        progressView.observedProgress = progress

        self.view.addSubview(progressView)
        progressView.autoVCenterInSuperview()
        progressView.autoPinWidthToSuperview(withMargin: .scaleFromIPhone5(30))
        progressView.progressTintColor = Theme.accentBlueColor

        updateProgressViewVisibility()

        let label = UILabel()
        label.textColor = Theme.primaryTextColor
        label.font = .systemFont(ofSize: 17)
        label.text = OWSLocalizedString(
            "SHARE_EXTENSION_LOADING",
            comment: "Indicates that the share extension is still loading.",
        )
        self.view.addSubview(label)
        label.autoHCenterInSuperview()
        label.autoPinEdge(.top, to: .bottom, of: activityIndicator, withOffset: 12)
    }

    var preferredNavigationBarStyle: OWSNavigationBarStyle {
        // The false case should be the default, but we can't access the
        // extension's default implementation here.
        return self.shouldMimicRecipientPicker ? .solid : .blur
    }

    var navbarBackgroundColorOverride: UIColor? {
        // The false case should be the default, but we can't access the
        // extension's default implementation here.
        return self.shouldMimicRecipientPicker ? Theme.tableView2PresentedBackgroundColor : nil
    }
}
