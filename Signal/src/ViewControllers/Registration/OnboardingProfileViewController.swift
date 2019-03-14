//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public class OnboardingProfileViewController: OnboardingBaseViewController {

    // MARK: - Dependencies

    var profileManager: OWSProfileManager {
        return OWSProfileManager.shared()
    }

    // MARK: -

    private let avatarView = AvatarImageView()
    private let nameTextfield = UITextField()
    private var avatar: UIImage?
    private let cameraCircle = UIView.container()

    private let avatarViewHelper = AvatarViewHelper()

    override public func loadView() {
        super.loadView()

        avatarViewHelper.delegate = self

        view.backgroundColor = Theme.backgroundColor
        view.layoutMargins = .zero

        let titleLabel = self.titleLabel(text: NSLocalizedString("ONBOARDING_PROFILE_TITLE", comment: "Title of the 'onboarding profile' view."))
        titleLabel.accessibilityLabel = "onboarding.profile." + "titleLabel"

        let explanationLabel = self.explanationLabel(explanationText: NSLocalizedString("ONBOARDING_PROFILE_EXPLANATION",
                                                                                        comment: "Explanation in the 'onboarding profile' view."))
        explanationLabel.accessibilityLabel = "onboarding.profile." + "explanationLabel"

        let nextButton = self.button(title: NSLocalizedString("BUTTON_NEXT",
                                                              comment: "Label for the 'next' button."),
                                     selector: #selector(nextPressed))
        nextButton.accessibilityLabel = "onboarding.profile." + "nextButton"

        avatarView.autoSetDimensions(to: CGSize(width: CGFloat(avatarSize), height: CGFloat(avatarSize)))

        let cameraImageView = UIImageView()
        cameraImageView.image = UIImage(named: "settings-avatar-camera-2")?.withRenderingMode(.alwaysTemplate)
        cameraImageView.tintColor = Theme.secondaryColor
        cameraCircle.backgroundColor = Theme.backgroundColor
        cameraCircle.addSubview(cameraImageView)
        let cameraCircleDiameter: CGFloat = 40
        cameraCircle.autoSetDimensions(to: CGSize(width: cameraCircleDiameter, height: cameraCircleDiameter))
        cameraCircle.layer.shadowColor = UIColor(white: 0, alpha: 0.15).cgColor
        cameraCircle.layer.shadowRadius = 5
        cameraCircle.layer.shadowOffset = CGSize(width: 1, height: 1)
        cameraCircle.layer.shadowOpacity = 1
        cameraCircle.layer.cornerRadius = cameraCircleDiameter * 0.5
        cameraCircle.clipsToBounds = false
        cameraImageView.autoCenterInSuperview()

        let avatarWrapper = UIView.container()
        avatarWrapper.isUserInteractionEnabled = true
        avatarWrapper.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(avatarTapped)))
        avatarWrapper.addSubview(avatarView)
        avatarView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
        avatarWrapper.addSubview(cameraCircle)
        cameraCircle.autoPinEdge(toSuperviewEdge: .trailing)
        cameraCircle.autoPinEdge(toSuperviewEdge: .bottom)
        avatarWrapper.accessibilityLabel = "onboarding.profile." + "avatarWrapper"

        nameTextfield.textAlignment = .left
        nameTextfield.delegate = self
        nameTextfield.returnKeyType = .done
        nameTextfield.textColor = Theme.primaryColor
        nameTextfield.font = UIFont.ows_dynamicTypeBodyClamped
        nameTextfield.placeholder = NSLocalizedString("ONBOARDING_PROFILE_NAME_PLACEHOLDER",
                                                      comment: "Placeholder text for the profile name in the 'onboarding profile' view.")
        nameTextfield.setContentHuggingHorizontalLow()
        nameTextfield.setCompressionResistanceHorizontalLow()
        nameTextfield.accessibilityLabel = "onboarding.profile." + "nameTextfield"

        let nameWrapper = UIView.container()
        nameWrapper.setCompressionResistanceHorizontalLow()
        nameWrapper.setContentHuggingHorizontalLow()
        nameWrapper.addSubview(nameTextfield)
        nameTextfield.autoPinWidthToSuperview()
        nameTextfield.autoPinEdge(toSuperviewEdge: .top, withInset: 8)
        nameTextfield.autoPinEdge(toSuperviewEdge: .bottom, withInset: 8)
        _ = nameWrapper.addBottomStroke()

        let profileRow = UIStackView(arrangedSubviews: [
            avatarWrapper,
            nameWrapper
            ])
        profileRow.axis = .horizontal
        profileRow.alignment = .center
        profileRow.spacing = 8

        let topSpacer = UIView.vStretchingSpacer()
        let bottomSpacer = UIView.vStretchingSpacer()

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            topSpacer,
            profileRow,
            UIView.spacer(withHeight: 25),
            explanationLabel,
            bottomSpacer,
            nextButton
            ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.layoutMargins = UIEdgeInsets(top: 32, left: 32, bottom: 32, right: 32)
        stackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(stackView)
        stackView.autoPinWidthToSuperview()
        stackView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        autoPinView(toBottomOfViewControllerOrKeyboard: stackView, avoidNotch: true)

        // Ensure whitespace is balanced, so inputs are vertically centered.
        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)

        updateAvatarView()
    }

    private let avatarSize: UInt = 80

    private func updateAvatarView() {
        if let avatar = avatar {
            avatarView.image = avatar
            cameraCircle.isHidden = true
            return
        }

        let defaultAvatar = OWSContactAvatarBuilder(forLocalUserWithDiameter: avatarSize).buildDefaultImage()
        avatarView.image = defaultAvatar
        cameraCircle.isHidden = false
    }

     // MARK: -

    private func normalizedProfileName() -> String? {
        return nameTextfield.text?.ows_stripped()
    }

    private func tryToComplete() {

        let profileName = self.normalizedProfileName()
        let profileAvatar = self.avatar

        if profileName == nil, profileAvatar == nil {
            onboardingController.profileWasSkipped(fromView: self)
            return
        }

        if let name = profileName,
            profileManager.isProfileNameTooLong(name) {
            OWSAlerts.showErrorAlert(message: NSLocalizedString("PROFILE_VIEW_ERROR_PROFILE_NAME_TOO_LONG",
                                                                comment: "Error message shown when user tries to update profile with a profile name that is too long."))
            return
        }

        ModalActivityIndicatorViewController.present(fromViewController: self,
                                                     canCancel: true) { (modal) in

                                                        self.profileManager.updateLocalProfileName(profileName, avatarImage: profileAvatar, success: {
                                                            DispatchQueue.main.async {
                                                                modal.dismiss(completion: {
                                                                    self.onboardingController.profileDidComplete(fromView: self)
                                                                })
                                                            }
                                                        }, failure: {
                                                            DispatchQueue.main.async {
                                                                modal.dismiss(completion: {
                                                                    OWSAlerts.showErrorAlert(message: NSLocalizedString("PROFILE_VIEW_ERROR_UPDATE_FAILED",
                                                                                                                        comment: "Error message shown when a profile update fails."))
                                                                })
                                                            }
                                                        })
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        _ = nameTextfield.becomeFirstResponder()
    }

    // MARK: - Events

    @objc func avatarTapped(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            return
        }
        showAvatarActionSheet()
    }

    @objc func nextPressed() {
        Logger.info("")

        tryToComplete()
    }

    private func showAvatarActionSheet() {
        AssertIsOnMainThread()

        Logger.info("")

        avatarViewHelper.showChangeAvatarUI()
    }
}

// MARK: -

extension OnboardingProfileViewController: UITextFieldDelegate {
    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        tryToComplete()
        return false
    }
}

// MARK: -

extension OnboardingProfileViewController: AvatarViewHelperDelegate {
    public func avatarActionSheetTitle() -> String? {
        return nil
    }

    public func avatarDidChange(_ image: UIImage) {
        AssertIsOnMainThread()

        let maxDiameter = CGFloat(kOWSProfileManager_MaxAvatarDiameter)
        avatar = image.resizedImage(toFillPixelSize: CGSize(width: maxDiameter,
                                                            height: maxDiameter))

        updateAvatarView()
    }

    public func fromViewController() -> UIViewController {
        return self
    }

    public func hasClearAvatarAction() -> Bool {
        return avatar != nil
    }

    public func clearAvatar() {
        avatar = nil

        updateAvatarView()
    }

    public func clearAvatarActionLabel() -> String {
        return NSLocalizedString("PROFILE_VIEW_CLEAR_AVATAR", comment: "Label for action that clear's the user's profile avatar")
    }
}
