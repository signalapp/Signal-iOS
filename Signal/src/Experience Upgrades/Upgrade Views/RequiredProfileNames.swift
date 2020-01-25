//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import Lottie

class RequiredProfileNamesMegaphone: MegaphoneView {
    init(experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) {
        super.init(experienceUpgrade: experienceUpgrade)

        let hasProfileNameAlready = OWSProfileManager.shared().localFullName()?.isEmpty == false

        titleText = hasProfileNameAlready
            ? NSLocalizedString("REQUIRE_PROFILE_NAMES_MEGAPHONE_HAS_NAME_TITLE",
                                comment: "Title for required profile name megaphone when user already has a profile name")
            : NSLocalizedString("REQUIRE_PROFILE_NAMES_MEGAPHONE_NO_NAME_TITLE",
                                comment: "Title for required profile name megaphone when user doesn't have a profile name")
        bodyText = hasProfileNameAlready
            ? NSLocalizedString("REQUIRE_PROFILE_NAMES_MEGAPHONE_HAS_NAME_BODY",
                                comment: "Body for required profile name megaphone when user already has a profile name")
            : NSLocalizedString("REQUIRE_PROFILE_NAMES_MEGAPHONE_NO_NAME_BODY",
                                comment: "Body for required profile name megaphone when user doesn't have a profile name")
        imageName = "profileMegaphone"

        let primaryButton = MegaphoneView.Button(
            title: NSLocalizedString("REQUIRE_PROFILE_NAMES_MEGAPHONE_ACTION",
                                     comment: "Action text for required profile name megaphone")
        ) { [weak self] in
            let vc = ProfileViewController.forExperienceUpgrade {
                self?.markAsComplete()
                fromViewController.navigationController?.popToViewController(fromViewController, animated: true) {
                    fromViewController.navigationController?.setNavigationBarHidden(false, animated: false)
                    self?.dismiss(animated: false)
                    self?.presentToast(
                        text: NSLocalizedString("REQUIRE_PROFILE_NAMES_MEGAPHONE_TOAST",
                                                comment: "Toast indicating that a PIN has been created."),
                        fromViewController: fromViewController
                    )
                }
            }

            fromViewController.navigationController?.pushViewController(vc, animated: true)
        }

        let secondaryButton = snoozeButton(fromViewController: fromViewController)
        setButtons(primary: primaryButton, secondary: secondaryButton)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class RequiredProfileNamesSplash: SplashViewController {

    let animationView = AnimationView(name: "requiredProfileNamesSplash")

    var ows2FAManager: OWS2FAManager {
        return .shared()
    }

    var hasProfileNameAlready: Bool {
        return OWSProfileManager.shared().localFullName()?.isEmpty == false
    }

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

        let title: String
        let body: String

        if hasProfileNameAlready {
            title = NSLocalizedString("REQUIRE_PROFILE_NAMES_SPLASH_CONFIRMATION_TITLE",
                                      comment: "Header for required profile names splash screen when the user already has a profile name")
            body = NSLocalizedString("REQUIRE_PROFILE_NAMES_SPLASH_CONFIRMATION_DESCRIPTION",
                                     comment: "Body text for required profile names splash screen when the user already has a profile name")
        } else {
            title = NSLocalizedString("REQUIRE_PROFILE_NAMES_SPLASH_CREATION_TITLE",
                                      comment: "Header for required profile names splash screen when the user doesn't have a profile name")
            body = NSLocalizedString("REQUIRE_PROFILE_NAMES_SPLASH_CREATION_DESCRIPTION",
                                     comment: "Body text for required profile names splash screen when the user doesn't have a profile name")
        }

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
                                                 backgroundColor: .ows_signalBlue,
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
        let vc = ProfileViewController.forExperienceUpgrade { [weak self] in
            self?.dismiss(animated: true)
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    func primaryButtonTitle() -> String {
        return hasProfileNameAlready
            ? NSLocalizedString("REQUIRE_PROFILE_NAMES_SPLASH_CONFIRMATION_BUTTON",
                                comment: "Button to start a confirm profile name flow from the one time splash screen that appears after upgrading")
            : NSLocalizedString("REQUIRE_PROFILE_NAMES_SPLASH_CREATION_BUTTON",
                                comment: "Button to start a create profile name flow from the one time splash screen that appears after upgrading")
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        guard let fromViewController = presentingViewController else {
            return owsFailDebug("Trying to dismiss while not presented.")
        }

        super.dismiss(animated: flag) { [weak self] in
            self?.presentToast(
                text: NSLocalizedString("REQUIRE_PROFILE_NAMES_MEGAPHONE_TOAST",
                                        comment: "Toast indicating that a PIN has been created."),
                fromViewController: fromViewController
            )
            completion?()
        }
    }
}
