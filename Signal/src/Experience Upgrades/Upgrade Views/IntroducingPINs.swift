//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SafariServices

class IntroducingPinsMegaphone: MegaphoneView {
    init(experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) {
        super.init(experienceUpgrade: experienceUpgrade)

        titleText = NSLocalizedString("PINS_MEGAPHONE_TITLE", comment: "Title for PIN megaphone when user doesn't have a PIN")
        bodyText = NSLocalizedString("PINS_MEGAPHONE_BODY", comment: "Body for PIN megaphone when user doesn't have a PIN")
        imageName = "PIN_megaphone"

        let primaryButtonTitle = NSLocalizedString("PINS_MEGAPHONE_ACTION", comment: "Action text for PIN megaphone when user doesn't have a PIN")

        let primaryButton = MegaphoneView.Button(title: primaryButtonTitle) { [weak self] in
            let vc = PinSetupViewController.creating { _, error in
                if let error = error {
                    Logger.error("failed to create pin: \(error)")
                } else {
                    // success
                    self?.markAsComplete()
                }
                fromViewController.navigationController?.popToViewController(fromViewController, animated: true) {
                    fromViewController.navigationController?.setNavigationBarHidden(false, animated: false)
                    self?.dismiss(animated: false)
                    self?.presentToast(
                        text: NSLocalizedString("PINS_MEGAPHONE_TOAST", comment: "Toast indicating that a PIN has been created."),
                        fromViewController: fromViewController
                    )
                }
            }

            fromViewController.navigationController?.pushViewController(vc, animated: true)
        }

        let secondaryButton = snoozeButton(fromViewController: fromViewController) {
            let daysRemaining = ExperienceUpgradeManager.splashStartDay - experienceUpgrade.daysSinceFirstViewed
            assert(daysRemaining > 0)

            let toastFormat = NSLocalizedString("PINS_MEGAPHONE_SNOOZE_TOAST_FORMAT",
                                    comment: "Toast indication that the user will be reminded later to setup their PIN. Embeds {{time until mandatory}}")

            return String(format: toastFormat, daysRemaining)
        }

        setButtons(primary: primaryButton, secondary: secondaryButton)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class IntroducingPinsSplash: SplashViewController {
    override var isReadyToComplete: Bool { KeyBackupService.hasMasterKey }

    override var canDismissWithGesture: Bool { return false }

    // MARK: - View lifecycle

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: false)
    }

    override func loadView() {

        self.view = UIView.container()
        self.view.backgroundColor = Theme.backgroundColor

        let heroImageView = UIImageView()
        heroImageView.setImage(imageName: Theme.isDarkThemeEnabled ? "introducing-pins-dark" : "introducing-pins-light")
        if let heroImage = heroImageView.image {
            heroImageView.autoPinToAspectRatio(with: heroImage.size)
        } else {
            owsFailDebug("Missing hero image.")
        }
        view.addSubview(heroImageView)
        heroImageView.autoPinTopToSuperviewMargin(withInset: 10)
        heroImageView.autoHCenterInSuperview()
        heroImageView.setContentHuggingLow()
        heroImageView.setCompressionResistanceLow()

        let title = NSLocalizedString("UPGRADE_EXPERIENCE_INTRODUCING_PINS_SETUP_TITLE", comment: "Header for PINs splash screen")

        let attributedBody = NSMutableAttributedString(
            string: NSLocalizedString("UPGRADE_EXPERIENCE_INTRODUCING_PINS_SETUP_DESCRIPTION",
                                      comment: "Body text for PINs splash screen"),
            attributes: [
                .font: UIFont.ows_dynamicTypeBody,
                .foregroundColor: Theme.primaryTextColor
            ]
        )
        attributedBody.append("  ")
        attributedBody.append(CommonStrings.learnMore,
                                attributes: [
                                    .link: URL(string: "https://support.signal.org/hc/articles/360007059792")!,
                                    .font: UIFont.ows_dynamicTypeBody
            ]
        )

        let hMargin: CGFloat = ScaleFromIPhone5To7Plus(16, 24)

        // Title label
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.ows_dynamicTypeTitle1.ows_semibold
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.minimumScaleFactor = 0.5
        titleLabel.adjustsFontSizeToFitWidth = true
        view.addSubview(titleLabel)
        titleLabel.autoPinWidthToSuperview(withMargin: hMargin)
        // The title label actually overlaps the hero image because it has a long shadow
        // and we want the text to partially sit on top of this.
        titleLabel.autoPinEdge(.top, to: .bottom, of: heroImageView, withOffset: -10)
        titleLabel.setContentHuggingVerticalHigh()

        // Body label
        let bodyLabel = LinkingTextView()
        bodyLabel.attributedText = attributedBody
        bodyLabel.isUserInteractionEnabled = true
        bodyLabel.textColor = Theme.primaryTextColor
        bodyLabel.textAlignment = .center
        view.addSubview(bodyLabel)
        bodyLabel.autoPinWidthToSuperview(withMargin: hMargin)
        bodyLabel.autoPinEdge(.top, to: .bottom, of: titleLabel, withOffset: 6)
        bodyLabel.setContentHuggingVerticalHigh()

        // Primary button
        let primaryButton = OWSFlatButton.button(title: primaryButtonTitle(),
                                                 font: UIFont.ows_dynamicTypeBody.ows_semibold,
                                                 titleColor: .white,
                                                 backgroundColor: .ows_accentBlue,
                                                 target: self,
                                                 selector: #selector(didTapPrimaryButton))
        primaryButton.autoSetHeightUsingFont()
        view.addSubview(primaryButton)

        primaryButton.autoPinBottomToSuperviewMargin(withInset: ScaleFromIPhone5(10))
        primaryButton.autoPinWidthToSuperview(withMargin: hMargin)
        primaryButton.autoPinEdge(.top, to: .bottom, of: bodyLabel, withOffset: 28)
        primaryButton.setContentHuggingVerticalHigh()

        // More button
        let moreButton = UIButton()
        moreButton.setTemplateImageName("more-horiz-24", tintColor: Theme.primaryIconColor)
        moreButton.addTarget(self, action: #selector(didTapMoreButton), for: .touchUpInside)
        view.addSubview(moreButton)

        moreButton.autoSetDimensions(to: CGSize(square: 44))
        moreButton.autoPinEdge(toSuperviewSafeArea: .trailing, withInset: 8)
        moreButton.autoPinEdge(toSuperviewSafeArea: .top, withInset: 8)
    }

    @objc
    func didTapPrimaryButton(_ sender: UIButton) {
        let vc = PinSetupViewController.creating { [weak self] _, _ in
            self?.dismiss(animated: true)
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc
    func didTapMoreButton(_ sender: UIButton) {
        let actionSheet = ActionSheetController()
        actionSheet.addAction(OWSActionSheets.cancelAction)

        let learnMoreAction = ActionSheetAction(
            title: NSLocalizedString(
                "UPGRADE_EXPERIENCE_INTRODUCING_PINS_LEARN_MORE",
                comment: "Learn more action on the one time splash screen that appears after upgrading"
            )
        ) { [weak self] _ in
            guard let self = self else { return }
            let vc = SFSafariViewController(url: URL(string: "https://support.signal.org/hc/articles/360007059792")!)
            self.present(vc, animated: true, completion: nil)
        }
        actionSheet.addAction(learnMoreAction)

        let skipAction = ActionSheetAction(
            title: NSLocalizedString(
                "UPGRADE_EXPERIENCE_INTRODUCING_PINS_SKIP",
                comment: "Skip action on the one time splash screen that appears after upgrading"
            )
        ) { [weak self] _ in
            guard let self = self else { return }
            PinSetupViewController.disablePinWithConfirmation(fromViewController: self).done { [weak self] pinDisabled in
                guard pinDisabled else { return }
                self?.dismiss(animated: true)
            }.catch { [weak self] _ in
                guard let self = self else { return }
                OWSActionSheets.showActionSheet(
                    title: NSLocalizedString("PIN_DISABLE_ERROR_TITLE",
                                             comment: "Error title indicating that the attempt to disable a PIN failed."),
                    message: NSLocalizedString("PIN_DISABLE_ERROR_MESSAGE",
                                               comment: "Error body indicating that the attempt to disable a PIN failed.")
                ) { _ in
                    self.dismissWithoutCompleting(animated: true)
                }
            }
        }
        actionSheet.addAction(skipAction)

        presentActionSheet(actionSheet)
    }

    func primaryButtonTitle() -> String {
        return NSLocalizedString("UPGRADE_EXPERIENCE_INTRODUCING_PINS_CREATE_BUTTON",
                                 comment: "Button to start a create pin flow from the one time splash screen that appears after upgrading")
    }

    func secondaryButtonTitle() -> String {
        return CommonStrings.learnMore
    }

    var toastText: String {
        return KeyBackupService.hasBackedUpMasterKey
            ? NSLocalizedString("PINS_MEGAPHONE_TOAST", comment: "Toast indicating that a PIN has been created.")
            : NSLocalizedString("PINS_MEGAPHONE_TOAST_DISABLED", comment: "Toast indicating that a PIN has been disabled.")
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        guard let fromViewController = presentingViewController else {
            return //owsFailDebug("Trying to dismiss while not presented.")
        }

        super.dismiss(animated: flag) { [weak self] in
            if let self = self, !self.isDismissWithoutCompleting {
                self.presentToast(
                    text: self.toastText,
                    fromViewController: fromViewController
                )
            }
            completion?()
        }
    }
}
