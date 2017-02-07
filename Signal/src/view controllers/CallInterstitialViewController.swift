//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSCallInterstitialViewController)
class CallInterstitialViewController: UIViewController {

    let TAG = "[CallInterstitialViewController]"

    var wasCallCancelled = false
    let callToken: String!

    // MARK: Views

    var hasConstraints = false
    var blurView: UIVisualEffectView!
    var contentView: UIView!

    // MARK: Initializers

    @available(*, unavailable, message:"init is unavailable, use initWithCallToken")
    required init?(coder aDecoder: NSCoder) {
        assert(false)
        self.callToken = ""
        super.init(coder: aDecoder)
    }

    required init(callToken: String) {
        self.callToken = callToken
        super.init(nibName: nil, bundle: nil)
        observeNotifications()
    }

    func observeNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector:#selector(willResignActive),
                                               name:NSNotification.Name.UIApplicationWillResignActive,
                                               object:nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func willResignActive() {
        cancelCall()
    }

    // MARK: View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        createViews()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        blurView.layer.opacity = 0
        contentView.layer.opacity = 0
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        UIView.animate(withDuration: 0.3,
                       delay: 1.0,
                       options: UIViewAnimationOptions.curveLinear,
                       animations: {
                        self.blurView.layer.opacity = 1
                        self.contentView.layer.opacity = 1
        },
                       completion: nil)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        blurView.layer.removeAllAnimations()
        contentView.layer.removeAllAnimations()
    }

    // MARK: - Create Views

    func createViews() {
        assert(self.view != nil)

        // Dark blurred background.
        let blurEffect = UIBlurEffect(style: .dark)
        blurView = UIVisualEffectView(effect: blurEffect)
        blurView.isUserInteractionEnabled = false
        self.view.addSubview(blurView)

        contentView = UIView()
        self.view.addSubview(contentView)

        let dialingLabel = UILabel()
        dialingLabel.text = NSLocalizedString("CALL_INTERSTITIAL_CALLING_LABEL", comment: "Title for call interstitial view")
        dialingLabel.textColor = UIColor.white
        dialingLabel.font = UIFont.ows_lightFont(withSize:ScaleFromIPhone5To7Plus(32, 40))
        dialingLabel.textAlignment = .center
        contentView.addSubview(dialingLabel)

        let cancelCallButton = UIButton()
        cancelCallButton.setTitle(NSLocalizedString("TXT_CANCEL_TITLE", comment: "nil"),
                                  for:.normal)
        cancelCallButton.setTitleColor(UIColor.white, for:.normal)
        cancelCallButton.titleLabel?.font = UIFont.ows_lightFont(withSize:ScaleFromIPhone5To7Plus(26, 32))
        let buttonInset = ScaleFromIPhone5To7Plus(7, 9)
        cancelCallButton.titleEdgeInsets = UIEdgeInsets(top: buttonInset,
                                                        left: buttonInset,
                                                        bottom: buttonInset,
                                                        right: buttonInset)
        cancelCallButton.addTarget(self, action:#selector(cancelCallButtonPressed), for:.touchUpInside)
        contentView.addSubview(cancelCallButton)

        dialingLabel.autoPinWidthToSuperview()
        dialingLabel.autoVCenterInSuperview()

        cancelCallButton.autoSetDimension(.height, toSize:ScaleFromIPhone5To7Plus(50, 60))
        cancelCallButton.autoPinWidthToSuperview()
        cancelCallButton.autoPinEdge(toSuperviewEdge:.bottom, withInset:ScaleFromIPhone5To7Plus(23, 41))
    }

    // MARK: - Layout

    override func updateViewConstraints() {
        if !hasConstraints {
            // We only want to create our constraints once.
            //
            // Note that constraints are also created elsewhere.
            // This only creates the constraints for the top-level contents of the view.
            hasConstraints = true

            // Force creation of the view.
            let view = self.view
            assert(view != nil)

            // Dark blurred background.
            blurView.autoPinEdgesToSuperviewEdges()

            contentView.autoPinEdgesToSuperviewEdges()
        }

        super.updateViewConstraints()
    }

    // MARK: - Methods

    func cancelCall() {
        guard !wasCallCancelled else {
            return
        }
        wasCallCancelled = true

        assert(callToken != nil)
        let notificationName = CallService.callWasCancelledByInterstitialNotificationName()
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: notificationName), object: callToken)

        self.dismiss(animated: false)
    }

    // MARK: - Events

    func cancelCallButtonPressed(sender button: UIButton) {
        cancelCall()
    }
}
