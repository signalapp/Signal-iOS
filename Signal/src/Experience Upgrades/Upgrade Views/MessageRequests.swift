//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import Lottie

class MessageRequestsSplash: SplashViewController {

    let animationView = AnimationView(name: "messageRequestsSplash")

    override var canDismissWithGesture: Bool { return false }

    // MARK: - View lifecycle
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        animationView.play()
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: false)
    }

    override func loadView() {

        self.view = UIView.container()
        self.view.backgroundColor = Theme.backgroundColor

        animationView.contentMode = .scaleAspectFit
        animationView.loopMode = .playOnce
        animationView.backgroundBehavior = .forceFinish

        view.addSubview(animationView)
        animationView.autoPinTopToSuperviewMargin(withInset: 10)
        animationView.autoPinWidthToSuperview()
        animationView.setContentHuggingLow()
        animationView.setCompressionResistanceLow()

        let title = NSLocalizedString("MESSAGE_REQUESTS_NAMES_SPLASH_TITLE",
                                      comment: "Header for message requests splash screen")
        let body = NSLocalizedString("MESSAGE_REQUESTS_SPLASH_BODY",
                                     comment: "Body text for message requests splash screen")

        let hMargin: CGFloat = ScaleFromIPhone5To7Plus(16, 24)

        // Title label
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.ows_dynamicTypeTitle1.ows_semibold()
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.minimumScaleFactor = 0.5
        titleLabel.adjustsFontSizeToFitWidth = true
        view.addSubview(titleLabel)
        titleLabel.autoPinWidthToSuperview(withMargin: hMargin)
        // The title label actually overlaps the hero image because it has a long shadow
        // and we want the text to partially sit on top of this.
        titleLabel.autoPinEdge(.top, to: .bottom, of: animationView, withOffset: -10)
        titleLabel.setContentHuggingVerticalHigh()

        // Body label
        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.font = UIFont.ows_dynamicTypeBody
        bodyLabel.textColor = Theme.primaryTextColor
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.textAlignment = .center
        view.addSubview(bodyLabel)
        bodyLabel.autoPinWidthToSuperview(withMargin: hMargin)
        bodyLabel.autoPinEdge(.top, to: .bottom, of: titleLabel, withOffset: 6)
        bodyLabel.setContentHuggingVerticalHigh()

        // Primary button
        let primaryButton = OWSFlatButton.button(title: primaryButtonTitle(),
                                                 font: UIFont.ows_dynamicTypeBody.ows_semibold(),
                                                 titleColor: .white,
                                                 backgroundColor: .ows_accentBlue,
                                                 target: self,
                                                 selector: #selector(didTapPrimaryButton))
        primaryButton.autoSetHeightUsingFont()
        view.addSubview(primaryButton)

        primaryButton.autoPinWidthToSuperview(withMargin: hMargin)
        primaryButton.autoPinEdge(.top, to: .bottom, of: bodyLabel, withOffset: 28)
        primaryButton.setContentHuggingVerticalHigh()
        primaryButton.autoPinBottomToSuperviewMargin(withInset: ScaleFromIPhone5(10))
    }

    @objc
    func didTapPrimaryButton(_ sender: UIButton) {
        let vc = ProfileViewController(mode: .experienceUpgrade) { [weak self] _ in
            self?.dismiss(animated: true)
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    func primaryButtonTitle() -> String {
        return NSLocalizedString("MESSAGE_REQUESTS_SPLASH_ADD_PROFILE_NAME_BUTTON",
                                comment: "Button to start a create profile name flow from the one time splash screen that appears after upgrading")
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        guard let fromViewController = presentingViewController else {
            return owsFailDebug("Trying to dismiss while not presented.")
        }

        super.dismiss(animated: flag) { [weak self] in
            if let self = self, !self.isDismissWithoutCompleting {
                self.presentToast(
                    text: NSLocalizedString("MESSAGE_REQUESTS_SPLASH_MEGAPHONE_TOAST",
                                            comment: "Toast indicating that a profile name has been created."),
                    fromViewController: fromViewController
                )
            }
            completion?()
        }
    }
}
