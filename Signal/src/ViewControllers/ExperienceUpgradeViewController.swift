//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalMessaging
import SafariServices

private class IntroducingStickersExperienceUpgradeViewController: ExperienceUpgradeViewController {

    // MARK: - View lifecycle

    override func loadView() {
        self.view = UIView.container()
        self.view.backgroundColor = Theme.backgroundColor

        let heroImageView = UIImageView()
        heroImageView.setImage(imageName: "introducing-link-previews-dark")
        if let heroImage = heroImageView.image {
            heroImageView.autoPinToAspectRatio(with: heroImage.size)
        } else {
            owsFailDebug("Missing hero image.")
        }
        view.addSubview(heroImageView)
        heroImageView.autoPinTopToSuperviewMargin(withInset: 20)
        // TODO: Depending on the final asset, we might autoPinWidthToSuperview()
        // and add spacing  with the content below.
        heroImageView.autoHCenterInSuperview()
        heroImageView.setContentHuggingLow()
        heroImageView.setCompressionResistanceLow()

        let title = NSLocalizedString("UPGRADE_EXPERIENCE_INTRODUCING_STICKERS_TITLE", comment: "Header for stickers splash screen")
        let body = NSLocalizedString("UPGRADE_EXPERIENCE_INTRODUCING_STICKERS_DESCRIPTION", comment: "Body text for stickers splash screen")
        let hMargin: CGFloat = ScaleFromIPhone5To7Plus(16, 24)

        // Title label
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.ows_dynamicTypeTitle1.ows_mediumWeight()
        titleLabel.textColor = Theme.primaryColor
        titleLabel.minimumScaleFactor = 0.5
        titleLabel.adjustsFontSizeToFitWidth = true
        view.addSubview(titleLabel)
        titleLabel.autoPinWidthToSuperview(withMargin: hMargin)
        titleLabel.autoPinEdge(.top, to: .bottom, of: heroImageView, withOffset: 20)
        titleLabel.setContentHuggingVerticalHigh()

        // Body label
        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.font = UIFont.ows_dynamicTypeBody
        bodyLabel.textColor = Theme.primaryColor
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.textAlignment = .center
        view.addSubview(bodyLabel)
        bodyLabel.autoPinWidthToSuperview(withMargin: hMargin)
        bodyLabel.autoPinEdge(.top, to: .bottom, of: titleLabel, withOffset: 6)
        bodyLabel.setContentHuggingVerticalHigh()

        // Icon
        let iconImageView = UIImageView()
        iconImageView.setTemplateImageName("sticker-smiley-outline-24", tintColor: Theme.secondaryColor)
        iconImageView.layer.minificationFilter = .trilinear
        iconImageView.layer.magnificationFilter = .trilinear
        view.addSubview(iconImageView)
        iconImageView.autoHCenterInSuperview()
        iconImageView.autoPinEdge(.top, to: .bottom, of: bodyLabel, withOffset: 10)
        iconImageView.setContentHuggingHigh()
        iconImageView.setCompressionResistanceHigh()
        iconImageView.autoSetDimensions(to: CGSize(width: 34, height: 34))

        // Dismiss button
        let dismissButton = OWSFlatButton.button(title: dismissButtonTitle(),
                                                 font: UIFont.ows_dynamicTypeBody.ows_mediumWeight(),
                                                 titleColor: UIColor.white,
                                                 backgroundColor: UIColor.ows_materialBlue,
                                                 target: self,
                                                 selector: #selector(didTapDismissButton))
        dismissButton.autoSetHeightUsingFont()
        view.addSubview(dismissButton)

        dismissButton.autoPinBottomToSuperviewMargin(withInset: ScaleFromIPhone5(30))
        dismissButton.autoPinWidthToSuperview(withMargin: hMargin)
        dismissButton.autoPinEdge(.top, to: .bottom, of: iconImageView, withOffset: 30)
        dismissButton.setContentHuggingVerticalHigh()
    }

    func dismissButtonTitle() -> String {
        // This should be true for "Opt-in" features/upgrades.
        let useNotNowButton = false
        if useNotNowButton {
            // We keep this string literal here to preserve the translation.
            return NSLocalizedString("EXPERIENCE_UPGRADE_DISMISS_BUTTON",
                                     comment: "Button to dismiss/ignore the one time splash screen that appears after upgrading")
        } else {
            return NSLocalizedString("EXPERIENCE_UPGRADE_LETS_GO_BUTTON",
                                     comment: "Button to dismiss/ignore the one time splash screen that appears after upgrading")
        }
    }
}

private class IntroducingPinsExperienceUpgradeViewController: ExperienceUpgradeViewController {

    var ows2FAManager: OWS2FAManager {
        return .shared()
    }

    var hasPinAlready: Bool {
        // Treat users with legacy pins as not having a pin at all, so we
        // can migrate them off of their old, possibly truncated pins.
        return ows2FAManager.is2FAEnabled() && !ows2FAManager.needsLegacyPinMigration()
    }

    override var canDismissWithGesture: Bool {
        return hasPinAlready
    }

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
        heroImageView.setImage(imageName: "introducing-pins-\(Theme.isDarkThemeEnabled ? "dark" : "light")")
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

        let title: String
        let body: String

        if hasPinAlready {
            title = NSLocalizedString("UPGRADE_EXPERIENCE_INTRODUCING_PINS_MIGRATION_TITLE", comment: "Header for PINs migration splash screen")
            body = NSLocalizedString("UPGRADE_EXPERIENCE_INTRODUCING_PINS_MIGRATION_DESCRIPTION", comment: "Body text for PINs migration splash screen")
        } else {
            title = NSLocalizedString("UPGRADE_EXPERIENCE_INTRODUCING_PINS_SETUP_TITLE", comment: "Header for PINs splash screen")
            body = NSLocalizedString("UPGRADE_EXPERIENCE_INTRODUCING_PINS_SETUP_DESCRIPTION", comment: "Body text for PINs splash screen")
        }

        let hMargin: CGFloat = ScaleFromIPhone5To7Plus(16, 24)

        // Title label
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.ows_dynamicTypeTitle1.ows_semiBold()
        titleLabel.textColor = Theme.primaryColor
        titleLabel.minimumScaleFactor = 0.5
        titleLabel.adjustsFontSizeToFitWidth = true
        view.addSubview(titleLabel)
        titleLabel.autoPinWidthToSuperview(withMargin: hMargin)
        // The title label actually overlaps the hero image because it has a long shadow
        // and we want the text to partially sit on top of this.
        titleLabel.autoPinEdge(.top, to: .bottom, of: heroImageView, withOffset: -10)
        titleLabel.setContentHuggingVerticalHigh()

        // Body label
        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.font = UIFont.ows_dynamicTypeBody
        bodyLabel.textColor = Theme.primaryColor
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.textAlignment = .center
        view.addSubview(bodyLabel)
        bodyLabel.autoPinWidthToSuperview(withMargin: hMargin)
        bodyLabel.autoPinEdge(.top, to: .bottom, of: titleLabel, withOffset: 6)
        bodyLabel.setContentHuggingVerticalHigh()

        // Primary button
        let primaryButton = OWSFlatButton.button(title: primaryButtonTitle(),
                                                 font: UIFont.ows_dynamicTypeBody.ows_semiBold(),
                                                 titleColor: .white,
                                                 backgroundColor: .ows_materialBlue,
                                                 target: self,
                                                 selector: #selector(didTapPrimaryButton))
        primaryButton.autoSetHeightUsingFont()
        view.addSubview(primaryButton)

        primaryButton.autoPinWidthToSuperview(withMargin: hMargin)
        primaryButton.autoPinEdge(.top, to: .bottom, of: bodyLabel, withOffset: 28)
        primaryButton.setContentHuggingVerticalHigh()

        // Secondary button
        let secondaryButton = UIButton()
        secondaryButton.setTitle(secondaryButtonTitle(), for: .normal)
        secondaryButton.setTitleColor(.ows_materialBlue, for: .normal)
        secondaryButton.titleLabel?.font = .ows_dynamicTypeBody
        secondaryButton.addTarget(self, action: #selector(didTapSecondaryButton), for: .touchUpInside)
        view.addSubview(secondaryButton)

        secondaryButton.autoPinBottomToSuperviewMargin(withInset: ScaleFromIPhone5(10))
        secondaryButton.autoPinWidthToSuperview(withMargin: hMargin)
        secondaryButton.autoPinEdge(.top, to: .bottom, of: primaryButton, withOffset: 15)
        secondaryButton.setContentHuggingVerticalHigh()
    }

    @objc
    func didTapPrimaryButton(_ sender: UIButton) {
        if hasPinAlready {
            dismiss(animated: true)
        } else {
            let vc = PinSetupViewController { [weak self] in
                self?.dismiss(animated: true)
            }
            navigationController?.pushViewController(vc, animated: true)
        }
    }

    @objc
    func didTapSecondaryButton(_ sender: UIButton) {
        // TODO PINs: Open the right support center URL
        let vc = SFSafariViewController(url: URL(string: "https://support.signal.org/hc/en-us/articles/360007059792")!)
        present(vc, animated: true, completion: nil)
    }

    func primaryButtonTitle() -> String {
        if hasPinAlready {
            return NSLocalizedString("BUTTON_OKAY",
                                     comment: "Label for the 'okay' button.")
        } else {
            return NSLocalizedString("UPGRADE_EXPERIENCE_INTRODUCING_PINS_CREATE_BUTTON",
                                     comment: "Button to start a create pin flow from the one time splash screen that appears after upgrading")
        }
    }

    func secondaryButtonTitle() -> String {
        if hasPinAlready {
            return NSLocalizedString("UPGRADE_EXPERIENCE_INTRODUCING_PINS_LEARN_MORE_BUTTON",
                                     comment: "Button to open a help document explaining more about why a PIN is required")
        } else {
            return NSLocalizedString("UPGRADE_EXPERIENCE_INTRODUCING_PINS_WHY_BUTTON",
                                     comment: "Button to open a help document explaining more about why a PIN is required")
        }
    }
}

@objc
public class ExperienceUpgradeViewController: OWSViewController {

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    private let experienceUpgrade: ExperienceUpgrade
    fileprivate var canDismissWithGesture: Bool { return true }

    init(experienceUpgrade: ExperienceUpgrade) {
        self.experienceUpgrade = experienceUpgrade
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: - Factory

    @objc
    public class func viewController(forExperienceUpgrade experienceUpgrade: ExperienceUpgrade) -> UIViewController? {
        guard let identifier = ExperienceUpgradeId(rawValue: experienceUpgrade.uniqueId) else {
            owsFailDebug("unknown experience upgrade. skipping")
            return nil
        }

        switch identifier {
        case .introducingStickers:
            return IntroducingStickersExperienceUpgradeViewController(experienceUpgrade: experienceUpgrade)
        case .introducingPins:
            let vc = IntroducingPinsExperienceUpgradeViewController(experienceUpgrade: experienceUpgrade)
            return OWSNavigationController(rootViewController: vc)
        @unknown default:
            owsFailDebug("Unknown identifier: \(identifier)")
            return nil
        }
    }

    // MARK: - View lifecycle

    override public var preferredStatusBarStyle: UIStatusBarStyle {
        return Theme.isDarkThemeEnabled ? .lightContent : .default
    }

    @objc
    public override func viewDidLoad() {
        super.viewDidLoad()

        addDismissGesture()
    }

    // MARK: -

    fileprivate func addDismissGesture() {
        let swipeGesture = UISwipeGestureRecognizer(target: self, action: #selector(handleDismissGesture))
        swipeGesture.direction = .down
        view.addGestureRecognizer(swipeGesture)
        view.isUserInteractionEnabled = true
    }

    @objc
    public override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        // Blocking write before dismiss, to be sure they're marked as complete
        // before HomeView.didAppear is re-fired.
        databaseStorage.write { transaction in
            Logger.info("marking all upgrades as seen.")
            ExperienceUpgradeFinder.shared.markAsSeen(experienceUpgrade: self.experienceUpgrade,
                                                      transaction: transaction)
        }
        super.dismiss(animated: flag, completion: completion)
    }

    @objc
    func didTapDismissButton(sender: UIButton) {
        Logger.debug("")
        self.dismiss(animated: true)
    }

    @objc
    func handleDismissGesture(sender: AnyObject) {
        guard canDismissWithGesture else { return }

        Logger.debug("")
        self.dismiss(animated: true)
    }

    // MARK: Orientation

    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
}
