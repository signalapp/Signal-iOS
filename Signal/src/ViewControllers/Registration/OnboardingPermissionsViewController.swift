//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit
import PromiseKit

@objc
public class OnboardingPermissionsViewController: OWSViewController {
    // Unlike a delegate, the OnboardingController we should retain a strong
    // reference to the onboardingController.
    private var onboardingController: OnboardingController

    @objc
    public init(onboardingController: OnboardingController) {
        self.onboardingController = onboardingController

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: -

    override public func loadView() {
        super.loadView()

        view.backgroundColor = Theme.backgroundColor
        view.layoutMargins = UIEdgeInsets(top: 32, left: 32, bottom: 32, right: 32)

        // TODO:
//        navigationItem.title = NSLocalizedString("SETTINGS_BACKUP", comment: "Label for the backup view in app settings.")

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("NAVIGATION_ITEM_SKIP_BUTTON", comment: "A button to skip a view."),
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(skipWasPressed))

        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("ONBOARDING_PERMISSIONS_TITLE", comment: "Title of the 'onboarding permissions' view.")
        titleLabel.textColor = Theme.primaryColor
        titleLabel.font = UIFont.ows_dynamicTypeTitle2.ows_mediumWeight()
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center
        view.addSubview(titleLabel)
        titleLabel.autoPinWidthToSuperviewMargins()
        titleLabel.autoPinEdge(toSuperviewMargin: .top)

        let explainerLabel = UILabel()
        // TODO: Finalize copy.
        explainerLabel.text = NSLocalizedString("ONBOARDING_PERMISSIONS_EXPLANATION", comment: "Explanation in the 'onboarding permissions' view.")
        explainerLabel.textColor = Theme.secondaryColor
        explainerLabel.font = UIFont.ows_dynamicTypeCaption1
        explainerLabel.numberOfLines = 0
        explainerLabel.textAlignment = .center
        explainerLabel.lineBreakMode = .byWordWrapping
        explainerLabel.isUserInteractionEnabled = true
        explainerLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(explainerLabelTapped)))

        // TODO: Make sure this all fits if dynamic font sizes are maxed out.
        let buttonHeight: CGFloat = 48
        let giveAccessButton = OWSFlatButton.button(title: NSLocalizedString("ONBOARDING_PERMISSIONS_GIVE_ACCESS_BUTTON",
                                                                             comment: "Label for the 'give access' button in the 'onboarding permissions' view."),
                                                    font: OWSFlatButton.fontForHeight(buttonHeight),
                                                    titleColor: .white,
                                                    backgroundColor: .ows_materialBlue,
                                                    target: self,
                                                    selector: #selector(giveAccessPressed))
        giveAccessButton.autoSetDimension(.height, toSize: buttonHeight)

        let notNowButton = OWSFlatButton.button(title: NSLocalizedString("ONBOARDING_PERMISSIONS_GIVE_ACCESS_BUTTON",
                                                                             comment: "Label for the 'give access' button in the 'onboarding permissions' view."),
                                                font: OWSFlatButton.fontForHeight(buttonHeight),
                                                    titleColor: .white,
                                                    backgroundColor: .ows_materialBlue,
                                                    target: self,
                                                    selector: #selector(notNowPressed))
        notNowButton.autoSetDimension(.height, toSize: buttonHeight)

        let buttonStack = UIStackView(arrangedSubviews: [
            giveAccessButton,
            notNowButton
            ])
        buttonStack.axis = .vertical
        buttonStack.alignment = .fill
        buttonStack.spacing = 12

        let stackView = UIStackView(arrangedSubviews: [
            explainerLabel,
            buttonStack
            ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 40
        view.addSubview(stackView)
        stackView.autoPinWidthToSuperviewMargins()
        stackView.autoVCenterInSuperview()
        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            stackView.autoPinEdge(.top, to: .bottom, of: titleLabel, withOffset: 20, relation: .greaterThanOrEqual)
        }
    }

    // MARK: Request Access

    private func requestAccess() {
        Logger.info("")

        // TODO: We need to defer app's request notification permissions until onboarding is complete.
        requestContactsAccess().then { _ in
            return PushRegistrationManager.shared.registerUserNotificationSettings()
        }.done { [weak self] in
            guard let self = self else {
                return
            }
            self.onboardingController.onboardingPermissionsDidComplete(viewController: self)
            }.retainUntilComplete()
    }

    private func requestContactsAccess() -> Promise<Void> {
        Logger.info("")

        let (promise, resolver) = Promise<Void>.pending()
        CNContactStore().requestAccess(for: CNEntityType.contacts) { (granted, error) -> Void in
            if granted {
                Logger.info("Granted.")
            } else {
                Logger.error("Error: \(String(describing: error)).")
            }
            // Always fulfill.
            resolver.fulfill(())
        }
        return promise
    }

    // MARK: Orientation

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

     // MARK: - Events

    @objc func skipWasPressed() {
        Logger.info("")

        onboardingController.onboardingPermissionsWasSkipped(viewController: self)
    }

    @objc func explainerLabelTapped(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            return
        }
        // TODO:
    }

    @objc func giveAccessPressed() {
        Logger.info("")

        requestAccess()
    }

    @objc func notNowPressed() {
        Logger.info("")

        delegate?.onboardingPermissionsWasSkipped(viewController: self)
    }
}
