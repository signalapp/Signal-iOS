//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Combine
import LibSignalClient
import SignalServiceKit
import SignalUI

// MARK: - RegistrationCaptchaPresenter

protocol RegistrationSignalLoginPresenter: RegistrationMethodPresenter {
    func submitLogin(
        aci: Aci,
        aep: SignalServiceKit.AccountEntropyPool,
    )
}

// MARK: - RegistrationEnterAccountViewState

public struct RegistrationSignalLoginState: Equatable {
    let aci: Aci?
    let aep: SignalServiceKit.AccountEntropyPool?
}

// MARK: - RegistrationCaptchaViewController

class RegistrationSignalLoginViewController: OWSViewController {

    private enum Constants {
        static let stackEdgeInsets = NSDirectionalEdgeInsets(top: 0, leading: 18, bottom: 10, trailing: 18)
        static let sectionSpacing: CGFloat = 8
        static let bodyLabelMargins: CGFloat = 20
    }

    private let state: RegistrationSignalLoginState
    private weak var presenter: RegistrationSignalLoginPresenter?

    private var titleImageView: UIImageView!

    private var titleLabel: UILabel!
    private var bodyLabel: UILabel!

    private var loginView: SignalLoginView!
    private var cancellables = Set<AnyCancellable>()

    init(
        state: RegistrationSignalLoginState,
        presenter: RegistrationSignalLoginPresenter,
    ) {
        self.state = state
        self.presenter = presenter

        super.init()
        navigationItem.hidesBackButton = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        // X (cancel) --- "Next"

        navigationItem.leftBarButtonItem = .closeButton { [weak self] in
            self?.presenter?.cancelChosenRestoreMethod()
        }

        navigationItem.rightBarButtonItem = .nextButton { [weak self] in
            self?.didTapNext()
        }
        navigationItem.rightBarButtonItem?.isEnabled = false

        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.directionalLayoutMargins = Constants.stackEdgeInsets
        stackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(stackView)
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = Constants.sectionSpacing
        let constraint = stackView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        constraint.priority = .defaultLow
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            constraint,
            stackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        ])

        // Login image
        titleImageView = UIImageView(image: .signalLogin)
        titleImageView.translatesAutoresizingMaskIntoConstraints = false
        titleImageView.contentMode = .center
        stackView.addArrangedSubview(titleImageView)
        stackView.setCustomSpacing(16, after: titleImageView)

        // Login Title

        titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(titleLabel)
        titleLabel.font = UIFont.dynamicTypeTitle2.semibold()
        titleLabel.textColor = .Signal.label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1
        titleLabel.text = OWSLocalizedString(
            "REGISTRATION_SIGNAL_LOGIN_TITLE",
            comment: "Title text for the 'Signal Login' screen.",
        )

        // Login Body

        bodyLabel = UILabel()
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.font = UIFont.dynamicTypeSubheadlineClamped
        bodyLabel.textColor = .Signal.secondaryLabel
        bodyLabel.numberOfLines = 0
        bodyLabel.textAlignment = .center
        bodyLabel.text = OWSLocalizedString(
            "REGISTRATION_SIGNAL_LOGIN_BODY",
            comment: "Description for the 'Signal Login' screen.",
        )

        let bodyLabelContainer = UIView.transparentContainer()
        bodyLabelContainer.translatesAutoresizingMaskIntoConstraints = false
        bodyLabelContainer.addSubview(bodyLabel)
        stackView.addArrangedSubview(bodyLabelContainer)
        stackView.setCustomSpacing(16, after: bodyLabelContainer)
        NSLayoutConstraint.activate([
            bodyLabel.topAnchor.constraint(equalTo: bodyLabelContainer.topAnchor),
            bodyLabel.bottomAnchor.constraint(equalTo: bodyLabelContainer.bottomAnchor),
            bodyLabel.centerXAnchor.constraint(equalTo: bodyLabelContainer.centerXAnchor),
            bodyLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: bodyLabelContainer.leadingAnchor,
                constant: Constants.bodyLabelMargins,
            ),
            bodyLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: bodyLabelContainer.trailingAnchor,
                constant: -Constants.bodyLabelMargins,
            ),
        ])

        // Signal Login view

        let displayableAEP = state.aep.map(DisplayableAccountEntropyPool.init(aep:))
        let loginView = SignalLoginView(
            aci: state.aci,
            displayableAEP: displayableAEP,
        )
        stackView.addArrangedSubview(loginView)
        loginView.translatesAutoresizingMaskIntoConstraints = false
        // `view` is the common ancestor of everything the card's height change moves,
        // so flushing here keeps each moved view's origin and size in a single
        // animation transaction. `[weak self]` because view -> stackView -> loginView
        // -> this closure would otherwise retain the view controller.
        loginView.didToggleRecoveryKeyView = { [weak self] animated in
            guard let self else { return }
            if animated {
                UIView.animate(withDuration: 0.2) {
                    self.view.layoutIfNeeded()
                }
            } else {
                self.view.setNeedsLayout()
            }
        }
        self.loginView = loginView

        loginView.signalLoginValuePublisher
            .sink { [weak self] (aciValue, aepValue) in
                switch (aciValue, aepValue) {
                case (.valid, .valid):
                    self?.navigationItem.rightBarButtonItem?.isEnabled = true
                case
                    (.partial, .valid),
                    (.valid, .partial),
                    (.partial, .partial):
                    self?.navigationItem.rightBarButtonItem?.isEnabled = false
                }
            }
            .store(in: &cancellables)

        // Spacer.

        let spacer = SpacerView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        spacer.setContentCompressionResistancePriority(UILayoutPriority(1), for: .vertical)
        stackView.addArrangedSubview(spacer)

        // Help Button

        let helpButton = UIButton()
        var config = UIButton.Configuration.borderedProminent()
        if #available(iOS 26, *) {
            config = UIButton.Configuration.clearGlass()
        } else {
            config.cornerStyle = .capsule
        }
        config.title = OWSLocalizedString(
            "REGISTRATION_SIGNAL_LOGIN_NEED_HELP_TITLE",
            comment: "Title for help button for the 'Signal Login' screen.",
        )
        helpButton.configuration = config
        helpButton.tintColor = UIColor.Signal.accent
        helpButton.translatesAutoresizingMaskIntoConstraints = false

        let helpButtonContainer = UIView.transparentContainer()
        helpButtonContainer.translatesAutoresizingMaskIntoConstraints = false
        helpButtonContainer.addSubview(helpButton)
        stackView.addArrangedSubview(helpButtonContainer)
        NSLayoutConstraint.activate([
            helpButton.topAnchor.constraint(equalTo: helpButtonContainer.topAnchor),
            helpButton.bottomAnchor.constraint(equalTo: helpButtonContainer.bottomAnchor),
            helpButton.centerXAnchor.constraint(equalTo: helpButtonContainer.centerXAnchor),
            helpButton.leadingAnchor.constraint(greaterThanOrEqualTo: helpButtonContainer.leadingAnchor),
            helpButton.trailingAnchor.constraint(lessThanOrEqualTo: helpButtonContainer.trailingAnchor),
        ])
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        loginView.becomeFirstResponder()
    }

    @available(*, unavailable)
    override init() {
        owsFail("This should not be called")
    }

    private func didTapNext() {
        switch loginView.currentLoginValues {
        case (.valid(let aci), .valid(let aep)):
            presenter?.submitLogin(aci: aci, aep: aep)
        case
            (.valid, .partial),
            (.partial, .valid),
            (.partial, .partial):
            owsFailDebug("This should not be called with partial values")
        }
    }

    private func showHelp() {
        // REGISTRATION_SIGNAL_LOGIN_HELP_BODY
    }
}

// MARK: -

#if DEBUG

private class PreviewRegistrationEnterAccountPresenter: RegistrationSignalLoginPresenter {
    func submitLogin(
        aci: LibSignalClient.Aci,
        aep: SignalServiceKit.AccountEntropyPool,
    ) {
        print("ACI: \(aci) \n AEP: \(aep)")
    }

    func cancelChosenRestoreMethod() { }
}

@available(iOS 17, *)
#Preview("No Values") {
    let state = RegistrationSignalLoginState(aci: nil, aep: nil)
    let presenter = PreviewRegistrationEnterAccountPresenter()
    return UINavigationController(
        rootViewController: RegistrationSignalLoginViewController(
            state: state,
            presenter: presenter,
        ),
    )
}

@available(iOS 17, *)
#Preview("AEP & ACI") {
    let state = RegistrationSignalLoginState(
        aci: Aci.randomForTesting(),
        aep: AccountEntropyPool(),
    )
    let presenter = PreviewRegistrationEnterAccountPresenter()
    return UINavigationController(
        rootViewController: RegistrationSignalLoginViewController(
            state: state,
            presenter: presenter,
        ),
    )
}

#endif
