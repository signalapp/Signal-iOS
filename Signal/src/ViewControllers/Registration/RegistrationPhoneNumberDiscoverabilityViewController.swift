//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

protocol RegistrationPhoneNumberDiscoverabilityPresenter: AnyObject {
    func setPhoneNumberDiscoverability(_ isDiscoverable: Bool)
    var presentedAsModal: Bool { get }
}

public struct RegistrationPhoneNumberDiscoverabilityState: Equatable {
    let e164: E164
    let isDiscoverableByPhoneNumber: Bool
}

class RegistrationPhoneNumberDiscoverabilityViewController: OWSViewController {

    private enum Constants {
        static let continueButtonInsets: UIEdgeInsets = .init(
                 top: 16.0,
                 leading: 36.0,
                 bottom: 48,
                 trailing: 36.0
             )
             static let continueButtonEdgeInsets: UIEdgeInsets = .init(
                 hMargin: 0,
                 vMargin: 16
             )
    }

    private let state: RegistrationPhoneNumberDiscoverabilityState
    private weak var presenter: RegistrationPhoneNumberDiscoverabilityPresenter?

    public init(
        state: RegistrationPhoneNumberDiscoverabilityState,
        presenter: RegistrationPhoneNumberDiscoverabilityPresenter
    ) {
        self.state = state
        self.presenter = presenter
        self.isDiscoverableByPhoneNumber = state.isDiscoverableByPhoneNumber
        super.init()
        render()
    }

    @available(*, unavailable)
    public override init() {
        owsFail("This should not be called")
    }

    // MARK: State

    private var isDiscoverableByPhoneNumber: Bool = true {
        didSet { render() }
    }

    // MARK: Rendering

    private lazy var titleLabel: UILabel = {
        let result = UILabel.titleLabelForRegistration(text: OWSLocalizedString(
            "ONBOARDING_PHONE_NUMBER_DISCOVERABILITY_TITLE",
            comment: "Title of the 'onboarding phone number discoverability' view."
        ))
        result.accessibilityIdentifier = "registration.phoneNumberDiscoverability.titleLabel"
        return result
    }()

    private lazy var explanationLabel: UILabel = {
        let formattedPhoneNumber = state.e164.stringValue
        let explanationTextFormat = OWSLocalizedString(
            "ONBOARDING_PHONE_NUMBER_DISCOVERABILITY_EXPLANATION_FORMAT",
            comment: "Explanation of the 'onboarding phone number discoverability' view. Embeds {user phone number}"
        )

        let result = UILabel.explanationLabelForRegistration(
            text: String(format: explanationTextFormat, formattedPhoneNumber)
        )
        result.accessibilityIdentifier = "registration.phoneNumberDiscoverability.explanationLabel"

        return result
    }()

    private lazy var everybodyButton: ButtonRow = {
        let result = ButtonRow(title: PhoneNumberDiscoverability.nameForDiscoverability(true))
        result.handler = { [weak self] _ in
            self?.isDiscoverableByPhoneNumber = true
        }
        return result
    }()

    private lazy var nobodyButton: ButtonRow = {
        let result = ButtonRow(title: PhoneNumberDiscoverability.nameForDiscoverability(false))
        result.handler = { [weak self] _ in
            self?.isDiscoverableByPhoneNumber = false
        }
        return result
    }()

    private lazy var selectionDescriptionLabel: UILabel = {
        let result = UILabel()
        result.font = .dynamicTypeCaption1Clamped
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        return result
    }()

    private lazy var nextBarButton = UIBarButtonItem(
        title: CommonStrings.nextButton,
        style: .done,
        target: self,
        action: #selector(didTapSave),
        accessibilityIdentifier: "registration.phoneNumberDiscoverability.nextButton"
    )

    private lazy var continueButton: UIView = {
        let footerView = UIView()
        let continueButton = OWSFlatButton.insetButton(
            title: CommonStrings.continueButton,
            font: UIFont.dynamicTypeBodyClamped.semibold(),
            titleColor: .white,
            backgroundColor: .ows_accentBlue,
            target: self,
            selector: #selector(didTapSave))
        continueButton.accessibilityIdentifier = "registration.phoneNumberDiscoverability.saveButton"

        footerView.addSubview(continueButton)

        continueButton.contentEdgeInsets = Constants.continueButtonEdgeInsets
        continueButton.autoPinEdgesToSuperviewEdges(with: Constants.continueButtonInsets)

        return footerView
    }()

    public override func viewDidLoad() {
        super.viewDidLoad()
        initialRender()
    }

    public override func themeDidChange() {
        super.themeDidChange()
        render()
    }

    private func initialRender() {
        navigationItem.setHidesBackButton(true, animated: false)
        if !(presenter?.presentedAsModal ?? true) {
            navigationItem.rightBarButtonItem = nextBarButton
        }

        let descriptionLabelContainer = UIView()
        descriptionLabelContainer.addSubview(selectionDescriptionLabel)
        selectionDescriptionLabel.autoPinEdgesToSuperviewMargins()

        var stackSubviews = [
            titleLabel,
            .spacer(withHeight: 16),
            explanationLabel,
            .spacer(withHeight: 24),
            everybodyButton,
            nobodyButton,
            .spacer(withHeight: 16),
            descriptionLabelContainer,
            .vStretchingSpacer(minHeight: 16)
        ]

        if presenter?.presentedAsModal ?? false {
            stackSubviews.append(contentsOf: [
                continueButton,
                .spacer(withHeight: 16)
            ])
        }

        let stackView = UIStackView(arrangedSubviews: stackSubviews)
        stackView.axis = .vertical
        view.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        render()
    }

    private func render() {
        everybodyButton.isSelected = isDiscoverableByPhoneNumber
        everybodyButton.render()

        nobodyButton.isSelected = !isDiscoverableByPhoneNumber
        nobodyButton.render()

        selectionDescriptionLabel.text = PhoneNumberDiscoverability.descriptionForDiscoverability(isDiscoverableByPhoneNumber)

        view.backgroundColor = Theme.backgroundColor
        continueButton.tintColor = Theme.accentBlueColor
        titleLabel.textColor = .colorForRegistrationTitleLabel
        explanationLabel.textColor = .colorForRegistrationExplanationLabel
        selectionDescriptionLabel.textColor = .colorForRegistrationExplanationLabel
    }

    // MARK: Events

    @objc
    private func didTapSave() {
        presenter?.setPhoneNumberDiscoverability(isDiscoverableByPhoneNumber)
    }
}

// MARK: - ButtonRow

private class ButtonRow: UIButton {
    var handler: ((ButtonRow) -> Void)?

    private let selectedImageView = UIImageView()

    static let vInset: CGFloat = 11
    static var hInset: CGFloat { UIDevice.current.isPlusSizePhone ? 20 : 16 }

    override var isSelected: Bool {
        didSet {
            selectedImageView.isHidden = !isSelected
        }
    }

    private lazy var buttonLabel: UILabel = UILabel()

    private lazy var divider: UIView = UIView()

    init(title: String) {
        super.init(frame: .zero)

        addTarget(self, action: #selector(didTap), for: .touchUpInside)

        buttonLabel.text = title

        selectedImageView.isHidden = true
        selectedImageView.contentMode = .scaleAspectFit
        selectedImageView.autoSetDimension(.width, toSize: 24)

        let stackView = UIStackView(arrangedSubviews: [buttonLabel, .hStretchingSpacer(), selectedImageView])
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

        addSubview(divider)
        divider.autoSetDimension(.height, toSize: .hairlineWidth)
        divider.autoPinEdge(toSuperviewEdge: .trailing)
        divider.autoPinEdge(toSuperviewEdge: .bottom)
        divider.autoPinEdge(toSuperviewEdge: .leading, withInset: Self.hInset)

        render()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func render() {
        setBackgroundImage(UIImage(color: Theme.cellSelectedColor), for: .highlighted)
        setBackgroundImage(UIImage(color: Theme.backgroundColor), for: .normal)

        buttonLabel.textColor = Theme.primaryTextColor
        buttonLabel.font = .dynamicTypeBodyClamped

        divider.backgroundColor = .ows_middleGray

        selectedImageView.setTemplateImage(Theme.iconImage(.checkmark), tintColor: Theme.primaryIconColor)
    }

    @objc
    func didTap() {
        handler?(self)
    }
}
