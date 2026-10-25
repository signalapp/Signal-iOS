//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI

// MARK: -

/// The two ways a user can get a Signal Login on the login selection screen.
public enum RegistrationSignalLoginSelection: Equatable {
    case purchaseLogin
    case existingLogin
}

// MARK: -

@MainActor
protocol RegistrationSignalLoginSplashPresenter: AnyObject {
    func exitSignalLogin()
    func submitLoginSelection(_ selection: RegistrationSignalLoginSelection)
}

// MARK: -

public struct RegistrationSignalLoginSplashState: Equatable {
    var formattedPrice: String
    let initialSelection: RegistrationSignalLoginSelection

    init(
        formattedPrice: String,
        initialSelection: RegistrationSignalLoginSelection = .purchaseLogin,
    ) {
        self.formattedPrice = formattedPrice
        self.initialSelection = initialSelection
    }
}

// MARK: -

final class RegistrationSignalLoginSplashViewController: OWSViewController {

    private enum Constants {
        static let buttonHorizontalMargin: CGFloat = 40
        static let buttonBottomMargin: CGFloat = 16
        static let contentToButtonSpacing: CGFloat = 16
        static let stackViewHorizontalMargin: CGFloat = 20

        // TODO[#less]: Point this at the Signal Login support article once it exists.
        static let learnMoreURL: URL = .Support.generic
    }

    private let state: RegistrationSignalLoginSplashState
    private weak var presenter: (any RegistrationSignalLoginSplashPresenter)?

    private var selection: RegistrationSignalLoginSelection {
        didSet {
            guard selection != oldValue else { return }
            applySelection()
        }
    }

    @available(*, unavailable)
    override init() {
        owsFail("This should not be called")
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init(state: RegistrationSignalLoginSplashState, presenter: any RegistrationSignalLoginSplashPresenter) {
        self.state = state
        self.presenter = presenter
        self.selection = state.initialSelection
        super.init()
    }

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    private lazy var titleImageView: UIImageView = {
        let result = UIImageView(image: .signalLogin)
        result.translatesAutoresizingMaskIntoConstraints = false
        result.contentMode = .center
        return result
    }()

    private lazy var titleLabel: UILabel = {
        UILabel.titleLabelForRegistration(
            text: OWSLocalizedString(
                "REGISTRATION_SIGNAL_LOGIN_TITLE",
                comment: "Title text for the 'Signal Login' screen.",
            ),
        )
    }()

    private lazy var bodyTextView: LinkingTextView = {
        let bodyTextView = LinkingTextView(overrideLinkAction: { [weak self] in
            self?.didTapLearnMore()
        })
        bodyTextView.translatesAutoresizingMaskIntoConstraints = false
        bodyTextView.textAlignment = .center
        bodyTextView.linkTextAttributes = [.foregroundColor: UIColor.Signal.label]
        bodyTextView.attributedText = {
            let result = NSMutableAttributedString(
                string: OWSLocalizedString(
                    "REGISTRATION_SIGNAL_LOGIN_EXPLANATION",
                    comment: "Explanation text for the 'Signal Login' screen.",
                ),
                attributes: [
                    .font: UIFont.dynamicTypeSubheadlineClamped,
                    .foregroundColor: UIColor.Signal.secondaryLabel,
                    .paragraphStyle: {
                        let paragraphStyle = NSMutableParagraphStyle()
                        paragraphStyle.alignment = .center
                        return paragraphStyle
                    }(),
                ],
            )
            result.append(NSAttributedString(
                string: " " + CommonStrings.learnMore,
                attributes: [
                    .font: UIFont.dynamicTypeSubheadlineClamped.semibold(),
                    .link: Constants.learnMoreURL,
                ],
            ))
            return result
        }()
        return bodyTextView
    }()

    private lazy var purchaseOptionView: SignalLoginOptionView = {
        SignalLoginOptionView(
            title: state.formattedPrice,
            subtitle: OWSLocalizedString(
                "REGISTRATION_SIGNAL_LOGIN_SELECTION_PURCHASE_SUBTITLE",
                comment: "Subtitle for the option to buy a new Signal Login.",
            ),
            bullets: [
                BulletPoint(
                    icon: .devicePhoneSlash,
                    text: OWSLocalizedString(
                        "REGISTRATION_SIGNAL_LOGIN_SELECTION_PURCHASE_BULLET_NO_PHONE_NUMBER",
                        comment: "Text for a bullet point describing that a Signal Login lets you register without a phone number.",
                    ),
                ),
                BulletPoint(
                    icon: .at,
                    text: OWSLocalizedString(
                        "REGISTRATION_SIGNAL_LOGIN_SELECTION_PURCHASE_BULLET_USERNAME",
                        comment: "Text for a bullet point describing that a Signal Login comes with a username for messaging and calling.",
                    ),
                ),
                BulletPoint(
                    icon: .heart,
                    text: OWSLocalizedString(
                        "REGISTRATION_SIGNAL_LOGIN_SELECTION_PURCHASE_BULLET_NON_PROFIT",
                        comment: "Text for a bullet point explaining that buying a Signal Login supports Signal, a non-profit.",
                    ),
                ),
            ],
            primaryAction: UIAction { [weak self] _ in
                self?.selection = .purchaseLogin
            },
        )
    }()

    private lazy var existingLoginOptionView: SignalLoginOptionView = {
        SignalLoginOptionView(
            title: OWSLocalizedString(
                "REGISTRATION_SIGNAL_LOGIN_SELECTION_EXISTING_TITLE",
                comment: "Title for the option to register with a Signal Login the user already owns.",
            ),
            subtitle: OWSLocalizedString(
                "REGISTRATION_SIGNAL_LOGIN_SELECTION_EXISTING_SUBTITLE",
                comment: "Subtitle for the option to register with a Signal Login the user already owns.",
            ),
            bullets: [
                BulletPoint(
                    icon: .devicePhone,
                    text: OWSLocalizedString(
                        "REGISTRATION_SIGNAL_LOGIN_SELECTION_EXISTING_BULLET_RESTORE",
                        comment: "Text for a bullet point describing that an existing Signal Login can be used to log in and restore an account.",
                    ),
                ),
                BulletPoint(
                    icon: .heart,
                    text: OWSLocalizedString(
                        "REGISTRATION_SIGNAL_LOGIN_SELECTION_EXISTING_BULLET_THANKS",
                        comment: "Text for a bullet point thanking the user for supporting Signal by previously buying a Signal Login.",
                    ),
                ),
            ],
            primaryAction: UIAction { [weak self] _ in
                self?.selection = .existingLogin
            },
        )
    }()

    private lazy var continueButton = {
        let button = UIButton(
            configuration: .largePrimary(title: payText()),
            primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                self.presenter?.submitLoginSelection(self.selection)
            },
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var buttonContainer = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Constants.contentToButtonSpacing,
            leading: Constants.buttonHorizontalMargin,
            bottom: Constants.buttonBottomMargin,
            trailing: Constants.buttonHorizontalMargin,
        )
        container.insetsLayoutMarginsFromSafeArea = false
        container.addSubview(continueButton)
        NSLayoutConstraint.activate([
            continueButton.topAnchor.constraint(equalTo: container.layoutMarginsGuide.topAnchor),
            continueButton.bottomAnchor.constraint(equalTo: container.layoutMarginsGuide.bottomAnchor),
            continueButton.leadingAnchor.constraint(equalTo: container.layoutMarginsGuide.leadingAnchor),
            continueButton.trailingAnchor.constraint(equalTo: container.layoutMarginsGuide.trailingAnchor),
        ])
        return container
    }()

    private func payText() -> String {
        let payFormat = OWSLocalizedString(
            "REGISTRATION_SIGNAL_LOGIN_PAY",
            comment: "Button to initiate a purchase on the 'Signal Login' screen. The replacement is a localized cost (e.g., $2.99).",
        )
        return String.nonPluralLocalizedStringWithFormat(payFormat, self.state.formattedPrice)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        let stackView = UIStackView(arrangedSubviews: [
            titleImageView,
            titleLabel,
            bodyTextView,
            purchaseOptionView,
            existingLoginOptionView,
        ])
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.addSubview(stackView)
        view.addSubview(scrollView)
        view.addSubview(buttonContainer)

        NSLayoutConstraint.activate([
            scrollView.frameLayoutGuide.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.frameLayoutGuide.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.frameLayoutGuide.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.frameLayoutGuide.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor,
                constant: Constants.stackViewHorizontalMargin,
            ),
            stackView.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor,
                constant: Constants.stackViewHorizontalMargin,
            ),
            stackView.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor,
                constant: -(Constants.stackViewHorizontalMargin * 2),
            ),

            buttonContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            buttonContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            buttonContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        if #available(iOS 26, *) {
            let interaction = UIScrollEdgeElementContainerInteraction()
            interaction.edge = .bottom
            interaction.scrollView = scrollView
            buttonContainer.addInteraction(interaction)
        }

        navigationItem.hidesBackButton = true
        navigationItem.leftBarButtonItem = .cancelButton { [weak self] in
            self?.presenter?.exitSignalLogin()
        }

        applySelection()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // The area covered by the button, above the safe area. The scroll
        // view's automatic inset adjustment already accounts for the safe area.
        let safeAreaBottom = view.bounds.height - view.safeAreaInsets.bottom
        let buttonOverlap = safeAreaBottom - buttonContainer.frame.minY
        if scrollView.contentInset.bottom != buttonOverlap {
            scrollView.contentInset.bottom = buttonOverlap
            scrollView.verticalScrollIndicatorInsets.bottom = buttonOverlap
        }
    }

    // MARK: - Selection

    private func applySelection() {
        purchaseOptionView.isSelected = selection == .purchaseLogin
        existingLoginOptionView.isSelected = selection == .existingLogin

        continueButton.configuration?.title = switch selection {
        case .purchaseLogin:
            payText()
        case .existingLogin:
            CommonStrings.continueButton
        }
    }

    // MARK: - Actions

    private func didTapLearnMore() {
        CurrentAppContext().open(Constants.learnMoreURL, completion: nil)
    }
}

// MARK: - SignalLoginOptionView

private struct BulletPoint {
    let icon: UIImage
    let text: String
}

/// A tappable card describing one way to get a Signal Login. The selected card
/// is outlined and shows a filled checkmark; the other shows an empty circle.
private class SignalLoginOptionView: UIControl {

    private enum Constants {
        static let cornerRadius: CGFloat = 16
        static let selectedBorderWidth: CGFloat = 2
        static let contentInsets = NSDirectionalEdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 16)
        static let selectionIndicatorSize: CGFloat = 24
        static let highlightedAlpha: CGFloat = 0.6
    }

    private let title: String
    private let subtitle: String
    private let bullets: [BulletPoint]

    private lazy var titleLabel: UILabel = {
        let result = UILabel()
        result.text = title
        result.textColor = .Signal.label
        result.font = UIFont.dynamicTypeTitle3.semibold()
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        result.textAlignment = .center
        return result
    }()

    private lazy var subtitleLabel: UILabel = {
        UILabel.explanationLabelForRegistration(text: subtitle)
    }()

    private let selectionIndicator = SelectionIndicatorView()

    override var isSelected: Bool {
        didSet {
            guard isSelected != oldValue else { return }
            selectionIndicator.isSelected = isSelected
            updateBorder()
        }
    }

    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? Constants.highlightedAlpha : 1
        }
    }

    init(
        title: String,
        subtitle: String,
        bullets: [BulletPoint],
        primaryAction: UIAction,
    ) {
        self.title = title
        self.subtitle = subtitle
        self.bullets = bullets

        super.init(frame: .zero)

        addAction(primaryAction, for: .touchUpInside)
        setUpSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor
    private func setUpSubviews() {
        translatesAutoresizingMaskIntoConstraints = false

        backgroundColor = .Signal.secondaryBackground
        layer.cornerRadius = Constants.cornerRadius
        layer.cornerCurve = .continuous
        updateBorder()

        let headerStackView = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        headerStackView.axis = .vertical
        headerStackView.alignment = .leading
        headerStackView.spacing = 2

        let headerRowStackView = UIStackView(arrangedSubviews: [headerStackView, selectionIndicator])
        headerRowStackView.axis = .horizontal
        headerRowStackView.alignment = .top
        headerRowStackView.spacing = 12

        let contentStackView = UIStackView(arrangedSubviews: [headerRowStackView])
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.axis = .vertical
        contentStackView.alignment = .fill
        contentStackView.spacing = 8
        contentStackView.setCustomSpacing(12, after: headerRowStackView)
        contentStackView.isUserInteractionEnabled = false

        contentStackView.addArrangedSubviews(bullets.map(BulletView.init(bullet:)))

        addSubview(contentStackView)
        NSLayoutConstraint.activate([
            selectionIndicator.widthAnchor.constraint(equalToConstant: Constants.selectionIndicatorSize),
            selectionIndicator.heightAnchor.constraint(equalToConstant: Constants.selectionIndicatorSize),

            contentStackView.topAnchor.constraint(
                equalTo: topAnchor,
                constant: Constants.contentInsets.top,
            ),
            contentStackView.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -Constants.contentInsets.bottom,
            ),
            contentStackView.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: Constants.contentInsets.leading,
            ),
            contentStackView.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -Constants.contentInsets.trailing,
            ),
        ])

    }

    private func updateBorder() {
        layer.borderColor = UIColor.Signal.ultramarine.cgColor
        layer.borderWidth = isSelected ? Constants.selectedBorderWidth : 0
    }
}

// MARK: BulletView

private class BulletView: UIView {

    private enum Constants {
        static let iconSize: CGFloat = 24
    }

    private let bullet: BulletPoint

    lazy var iconView: UIImageView = {
        let iconView = UIImageView(image: bullet.icon.withRenderingMode(.alwaysTemplate))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .Signal.label
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        return iconView
    }()

    lazy var label: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeSubheadlineClamped
        label.textColor = .Signal.label
        label.numberOfLines = 0
        label.text = bullet.text
        return label
    }()

    init(bullet: BulletPoint) {
        self.bullet = bullet
        super.init(frame: .zero)

        let stackView = UIStackView(arrangedSubviews: [iconView, label])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        stackView.axis = .horizontal
        stackView.alignment = .top
        stackView.spacing = 12

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Constants.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Constants.iconSize),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - SelectionIndicatorView

private class SelectionIndicatorView: UIView {

    private lazy var checkmarkView: UIImageView = {
        let imageView = UIImageView(
            image: UIImage(
                resource: .check,
            ).withRenderingMode(
                .alwaysTemplate,
            ),
        )
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    var isSelected: Bool = false {
        didSet {
            guard isSelected != oldValue else { return }
            updateAppearance()
        }
    }

    init() {
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false

        addSubview(checkmarkView)
        NSLayoutConstraint.activate([
            checkmarkView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            checkmarkView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            checkmarkView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            checkmarkView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
        ])

        layer.borderWidth = 2
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    private func updateAppearance() {
        checkmarkView.tintColor = .Signal.ColorBase.labelPrimary
        checkmarkView.isHidden = !isSelected
        backgroundColor = isSelected ? .Signal.ultramarine : .clear
        layer.borderColor = isSelected
            ? UIColor.clear.cgColor
            : UIColor.Signal.tertiaryLabel.cgColor
    }
}

#if DEBUG

private class PreviewRegistrationSignalLoginSplashPresenter: RegistrationSignalLoginSplashPresenter {
    func submitLoginSelection(_ selection: RegistrationSignalLoginSelection) {
        switch selection {
        case .existingLogin:
            print("Use Existing Login")
        case .purchaseLogin:
            print("Purchase Login")
        }
    }

    func exitSignalLogin() {
        print("Exit Login")
    }
}

@available(iOS 17, *)
#Preview("Purchase Selected") {
    let state = RegistrationSignalLoginSplashState(formattedPrice: "$2.99")
    let presenter = PreviewRegistrationSignalLoginSplashPresenter()
    return UINavigationController(
        rootViewController: RegistrationSignalLoginSplashViewController(
            state: state,
            presenter: presenter,
        ),
    )
}

@available(iOS 17, *)
#Preview("Existing Login Selected") {
    let state = RegistrationSignalLoginSplashState(formattedPrice: "$2.99")
    let presenter = PreviewRegistrationSignalLoginSplashPresenter()
    return UINavigationController(
        rootViewController: RegistrationSignalLoginSplashViewController(
            state: state,
            presenter: presenter,
        ),
    )
}

#endif
