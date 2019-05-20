//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalMessaging

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
        iconImageView.setTemplateImageName("sticker-filled-24", tintColor: Theme.secondaryColor)
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

@objc
public class ExperienceUpgradeViewController: OWSViewController {

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    private let experienceUpgrade: ExperienceUpgrade

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
        guard let uniqueId = experienceUpgrade.uniqueId else {
            Logger.error("experienceUpgrade is missing uniqueId.")
            return nil
        }
        guard let identifier = ExperienceUpgradeId(rawValue: uniqueId) else {
            owsFailDebug("unknown experience upgrade. skipping")
            return nil
        }

        switch identifier {
        case .introducingStickers:
            return IntroducingStickersExperienceUpgradeViewController(experienceUpgrade: experienceUpgrade)
        @unknown default:
            owsFailDebug("Unknown identifier: \(identifier)")
            return nil
        }
    }

    // MARK: - View lifecycle

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
        Logger.debug("")
        self.dismiss(animated: true)
    }

    // MARK: Orientation

    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
}
