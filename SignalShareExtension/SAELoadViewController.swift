//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import UIKit
import SignalMessaging
import PureLayout

class SAELoadViewController: UIViewController {

    weak var delegate: ShareViewDelegate?

    var activityIndicator: UIActivityIndicatorView!
    var progressView: UIProgressView!

    var progress: Progress? {
        didSet {
            guard progressView != nil else {
                return
            }

            updateProgressViewVisability()
            progressView.observedProgress = progress
        }
    }

    func updateProgressViewVisability() {
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

    init(delegate: ShareViewDelegate) {
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable, message:"use other constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    override func loadView() {
        super.loadView()

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel,
                                                                target: self,
                                                                action: #selector(cancelPressed))
        self.navigationItem.title = "Signal"

        self.view.backgroundColor = UIColor.ows_signalBrandBlue

        let activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .whiteLarge)
        self.activityIndicator = activityIndicator
        self.view.addSubview(activityIndicator)
        activityIndicator.autoCenterInSuperview()

        progressView = UIProgressView(progressViewStyle: .default)
        progressView.observedProgress = progress

        self.view.addSubview(progressView)
        progressView.autoVCenterInSuperview()
        progressView.autoPinWidthToSuperview(withMargin: ScaleFromIPhone5(30))
        progressView.progressTintColor = UIColor.white

        updateProgressViewVisability()

        let label = UILabel()
        label.textColor = UIColor.white
        label.font = UIFont.ows_mediumFont(withSize: 18)
        label.text = NSLocalizedString("SHARE_EXTENSION_LOADING",
                                       comment: "Indicates that the share extension is still loading.")
        self.view.addSubview(label)
        label.autoHCenterInSuperview()
        label.autoPinEdge(.top, to: .bottom, of: activityIndicator, withOffset: 25)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.navigationController?.isNavigationBarHidden = false
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

    }

    // MARK: - Event Handlers

    @objc func cancelPressed(sender: UIButton) {
        guard let delegate = delegate else {
            owsFailDebug("missing delegate")
            return
        }
        delegate.shareViewWasCancelled()
    }
}
