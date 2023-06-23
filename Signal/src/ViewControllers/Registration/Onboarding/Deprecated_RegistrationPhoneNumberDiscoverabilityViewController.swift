//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

public class Deprecated_RegistrationPhoneNumberDiscoverabilityViewController: Deprecated_OnboardingBaseViewController {

    static let hInset: CGFloat = UIDevice.current.isPlusSizePhone ? 20 : 16

    public override var primaryLayoutMargins: UIEdgeInsets {
        var defaultMargins = super.primaryLayoutMargins

        switch traitCollection.horizontalSizeClass {
        case .unspecified, .compact:
            defaultMargins.left = 0
            defaultMargins.right = 0
        case .regular:
            break
        @unknown default:
            break
        }

        return defaultMargins
    }

    private lazy var selectionDescriptionLabel = UILabel()
    private lazy var nobodyButton = ButtonRow(
        title: PhoneNumberDiscoverability.nameForDiscoverability(false)
    )
    private lazy var everybodyButton = ButtonRow(
        title: PhoneNumberDiscoverability.nameForDiscoverability(true)
    )
    private var isDiscoverableByPhoneNumber = true {
        didSet { updateSelections() }
    }

    // MARK: -

    override public func loadView() {
        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        view.backgroundColor = Theme.backgroundColor

        let titleLabel = self.createTitleLabel(text: OWSLocalizedString(
            "ONBOARDING_PHONE_NUMBER_DISCOVERABILITY_TITLE",
            comment: "Title of the 'onboarding phone number discoverability' view."
        ))
        titleLabel.accessibilityIdentifier = "onboarding.phoneNumberDiscoverability." + "titleLabel"

        var e164PhoneNumber = ""
        if let phoneNumber = TSAccountManager.localNumber {
            e164PhoneNumber = phoneNumber
        } else {
            owsFailDebug("missing phone number")
        }

        let formattedPhoneNumber =
            PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: e164PhoneNumber)
                .replacingOccurrences(of: " ", with: "\u{00a0}")

        let explanationTextFormat = OWSLocalizedString(
            "ONBOARDING_PHONE_NUMBER_DISCOVERABILITY_EXPLANATION_FORMAT",
            comment: "Explanation of the 'onboarding phone number discoverability' view. Embeds {user phone number}"
        )
        let explanationLabel = self.createExplanationLabel(
            explanationText: String(format: explanationTextFormat, formattedPhoneNumber)
        )
        explanationLabel.accessibilityIdentifier = "onboarding.phoneNumberDiscoverability." + "explanationLabel"

        let textStack = UIStackView(arrangedSubviews: [titleLabel, explanationLabel])
        textStack.axis = .vertical
        textStack.spacing = 16
        textStack.isLayoutMarginsRelativeArrangement = true
        textStack.layoutMargins = UIEdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32)

        everybodyButton.handler = { [weak self] _ in
            self?.isDiscoverableByPhoneNumber = true
        }
        nobodyButton.handler = { [weak self] _ in
            self?.isDiscoverableByPhoneNumber = false
        }

        selectionDescriptionLabel.font = .dynamicTypeCaption1Clamped
        selectionDescriptionLabel.textColor = .ows_gray45
        selectionDescriptionLabel.numberOfLines = 0
        selectionDescriptionLabel.lineBreakMode = .byWordWrapping

        let descriptionLabelContainer = UIView()
        descriptionLabelContainer.layoutMargins = UIEdgeInsets(
            top: 16,
            leading: Self.hInset,
            bottom: 0,
            trailing: 32
        )
        descriptionLabelContainer.addSubview(selectionDescriptionLabel)
        selectionDescriptionLabel.autoPinEdgesToSuperviewMargins()

        let nextButton = self.primaryButton(title: CommonStrings.nextButton,
                                           selector: #selector(nextPressed))
        nextButton.accessibilityIdentifier = "onboarding.phoneNumberDiscoverability." + "nextButton"
        let primaryButtonView = Deprecated_OnboardingBaseViewController.horizontallyWrap(primaryButton: nextButton)

        let compressableBottomMargin = UIView.vStretchingSpacer(minHeight: 16, maxHeight: primaryLayoutMargins.bottom)

        let stackView = UIStackView(arrangedSubviews: [
            textStack,
            .spacer(withHeight: 60),
            everybodyButton,
            nobodyButton,
            descriptionLabelContainer,
            .vStretchingSpacer(),
            primaryButtonView,
            compressableBottomMargin
            ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        primaryView.addSubview(stackView)

        stackView.autoPinEdgesToSuperviewMargins()
        updateSelections()
    }

    func updateSelections() {
        everybodyButton.isSelected = isDiscoverableByPhoneNumber
        nobodyButton.isSelected = !isDiscoverableByPhoneNumber

        selectionDescriptionLabel.text = PhoneNumberDiscoverability.descriptionForDiscoverability(isDiscoverableByPhoneNumber)
    }

    @objc
    func nextPressed() {
        guard let navigationController = navigationController else {
            owsFailDebug("Missing navigationController")
            return
        }

        SDSDatabaseStorage.shared.write { transaction in
            TSAccountManager.shared.setIsDiscoverableByPhoneNumber(
                self.isDiscoverableByPhoneNumber,
                updateStorageService: true,
                authedAccount: .implicit(),
                transaction: transaction
            )
        }

        onboardingController.showNextMilestone(navigationController: navigationController)
    }
}

private class ButtonRow: UIButton {
    var handler: ((ButtonRow) -> Void)?

    private let selectedImageView = UIImageView()

    static let vInset: CGFloat = 11
    static var hInset: CGFloat { Deprecated_RegistrationPhoneNumberDiscoverabilityViewController.hInset }

    override var isSelected: Bool {
        didSet {
            selectedImageView.isHidden = !isSelected
        }
    }

    init(title: String) {
        super.init(frame: .zero)

        addTarget(self, action: #selector(didTap), for: .touchUpInside)

        setBackgroundImage(UIImage(color: Theme.cellSelectedColor), for: .highlighted)
        setBackgroundImage(UIImage(color: Theme.backgroundColor), for: .normal)

        let titleLabel = UILabel()
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.font = .dynamicTypeBodyClamped
        titleLabel.text = title

        selectedImageView.isHidden = true
        selectedImageView.setTemplateImage(Theme.iconImage(.checkmark), tintColor: Theme.primaryIconColor)
        selectedImageView.contentMode = .scaleAspectFit
        selectedImageView.autoSetDimension(.width, toSize: 24)

        let stackView = UIStackView(arrangedSubviews: [titleLabel, .hStretchingSpacer(), selectedImageView])
        stackView.isUserInteractionEnabled = false
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = UIEdgeInsets(
            top: Self.vInset,
            leading: Self.hInset,
            bottom: Self.vInset,
            trailing: Self.hInset
        )

        addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()
        stackView.autoSetDimension(.height, toSize: 44, relation: .greaterThanOrEqual)

        let divider = UIView()
        divider.backgroundColor = .ows_middleGray
        addSubview(divider)
        divider.autoSetDimension(.height, toSize: .hairlineWidth)
        divider.autoPinEdge(toSuperviewEdge: .trailing)
        divider.autoPinEdge(toSuperviewEdge: .bottom)
        divider.autoPinEdge(toSuperviewEdge: .leading, withInset: Self.hInset)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func didTap() {
        handler?(self)
    }
}
