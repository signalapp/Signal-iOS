//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import UIKit
import SignalMessaging
import PureLayout

// All Observer methods will be invoked from the main thread.
protocol SAELoadViewDelegate: class {
    func shareExtensionWasCancelled()
    func shareExtensionIsReady()
}

class SAELoadViewController: UIViewController {

    weak var delegate: SAELoadViewDelegate?

    var activityIndicator: UIActivityIndicatorView?

    // MARK: Initializers and Factory Methods

    init(delegate: SAELoadViewDelegate) {
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable, message:"use other constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        fatalError("\(#function) is unimplemented.")
    }

    override func loadView() {
        super.loadView()

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel,
                                                                target: self,
                                                                action: #selector(cancelPressed))
        self.navigationItem.title = "Signal"

        self.view.backgroundColor = UIColor.ows_signalBrandBlue()

        let activityIndicator = UIActivityIndicatorView(activityIndicatorStyle:.whiteLarge)
        self.activityIndicator = activityIndicator
        self.view.addSubview(activityIndicator)
        activityIndicator.autoCenterInSuperview()

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

        guard let activityIndicator = activityIndicator else {
            return
        }
        activityIndicator.startAnimating()
    }

    override func viewDidAppear(_ animated: Bool) {
        // FIXME not until ready, and ideally before view appears to avoid any "loading flicker"
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1) {
            Logger.error("Simulating readiness...")
            self.delegate?.shareExtensionIsReady()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        guard let activityIndicator = activityIndicator else {
            return
        }
        activityIndicator.stopAnimating()
    }

    // MARK: - Event Handlers

    @objc func cancelPressed(sender: UIButton) {
        guard let delegate = delegate else {
            owsFail("\(self.logTag) missing delegate")
            return
        }
        delegate.shareExtensionWasCancelled()
    }
}
