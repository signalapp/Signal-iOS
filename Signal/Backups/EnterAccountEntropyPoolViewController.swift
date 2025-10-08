//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

class EnterAccountEntropyPoolViewController: OWSViewController {
    enum AEPValidationPolicy {
        case acceptAnyWellFormed
        case acceptOnly(AccountEntropyPool)
    }

    struct ColorConfig {
        let background: UIColor
        let aepEntryBackground: UIColor
    }

    struct HeaderStrings {
        let title: String
        let subtitle: String
    }

    struct FooterButtonConfig {
        let title: String
        let action: () -> Void
    }

    private var aepValidationPolicy: AEPValidationPolicy!
    private var colorConfig: ColorConfig!
    private var footerButtonConfig: FooterButtonConfig!
    private var headerStrings: HeaderStrings!
    private var onEntryConfirmed: ((AccountEntropyPool) -> Void)!

    func configure(
        aepValidationPolicy: AEPValidationPolicy,
        colorConfig: ColorConfig,
        headerStrings: HeaderStrings,
        footerButtonConfig: FooterButtonConfig,
        onEntryConfirmed: @escaping (AccountEntropyPool) -> Void,
    ) {
        self.aepValidationPolicy = aepValidationPolicy
        self.colorConfig = colorConfig
        self.headerStrings = headerStrings
        self.footerButtonConfig = footerButtonConfig
        self.onEntryConfirmed = onEntryConfirmed
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = colorConfig.background
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: CommonStrings.nextButton,
            style: .done,
            target: self,
            action: #selector(didTapNext)
        )

        let scrollView = UIScrollView()
        view.addSubview(scrollView)
        scrollView.preservesSuperviewLayoutMargins = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.frameLayoutGuide.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.frameLayoutGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.frameLayoutGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.frameLayoutGuide.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
        ])

        let titleLabel = UILabel.titleLabelForRegistration(text: headerStrings.title)
        let subtitleLabel = UILabel.explanationLabelForRegistration(text: headerStrings.subtitle)
        let footerButton = UIButton(
            configuration: .mediumSecondary(title: footerButtonConfig.title),
            primaryAction: UIAction { [weak self] _ in
                self?.footerButtonConfig.action()
            }
        )

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            subtitleLabel,
            aepTextView,
            aepIssueLabel,
            footerButton,
        ])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 24
        stackView.preservesSuperviewLayoutMargins = true
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.setCustomSpacing(16, after: aepTextView)
        stackView.setCustomSpacing(20, after: aepIssueLabel)
        stackView.setCustomSpacing(12, after: titleLabel)

        scrollView.addSubview(stackView)
        aepTextView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            aepTextView.widthAnchor.constraint(equalTo: stackView.layoutMarginsGuide.widthAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
        ])

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tapGesture)

        onTextViewUpdated()
    }

    // MARK: -

    private lazy var aepTextView = {
        let textView = AccountEntropyPoolTextView(mode: .entry(onTextViewChanged: { [weak self] in
            self?.onTextViewUpdated()
        }))
        textView.backgroundColor = colorConfig.aepEntryBackground
        return textView
    }()

    private lazy var aepIssueLabel: UILabel = {
        let label = UILabel()
        label.text = "This is never visible!" // Set in `onTextViewUpdated()`
        label.textColor = .ows_accentRed
        label.textAlignment = .center
        label.font = .dynamicTypeBody
        label.numberOfLines = 0
        return label
    }()

    // MARK: -

    @objc
    private func dismissKeyboard() {
        view.endEditing(true)
    }

    // MARK: -

    private enum AEPValidationResult {
        case notFullyEntered
        case malformedAEP
        case wellFormedButMismatched
        case success(AccountEntropyPool)
    }

    private func validateAEPText() -> AEPValidationResult {
        let enteredAepText = aepTextView.text.filter {
            $0.isNumber || $0.isLetter
        }

        guard enteredAepText.count == AccountEntropyPool.Constants.byteLength else {
            return .notFullyEntered
        }

        guard let enteredAep = try? AccountEntropyPool(key: enteredAepText) else {
            return .malformedAEP
        }

        switch aepValidationPolicy! {
        case .acceptAnyWellFormed:
            return .success(enteredAep)
        case .acceptOnly(let expectedAep):
            if enteredAep == expectedAep {
                return .success(enteredAep)
            } else {
                return .wellFormedButMismatched
            }
        }
    }

    private func onTextViewUpdated() {
        switch validateAEPText() {
        case .notFullyEntered:
            navigationItem.rightBarButtonItem?.isEnabled = false
            aepIssueLabel.alpha = 0
        case .malformedAEP:
            navigationItem.rightBarButtonItem?.isEnabled = false
            aepIssueLabel.text = OWSLocalizedString(
                "ENTER_ACCOUNT_ENTROPY_POOL_VIEW_MALFORMED_AEP_LABEL",
                comment: "Label explaining that an entered 'Recovery Key' is malformed."
            )
            aepIssueLabel.alpha = 1
        case .wellFormedButMismatched:
            navigationItem.rightBarButtonItem?.isEnabled = false
            aepIssueLabel.text = OWSLocalizedString(
                "ENTER_ACCOUNT_ENTROPY_POOL_VIEW_INCORRECT_AEP_LABEL",
                comment: "Label explaining that an entered 'Recovery Key' is incorrect."
            )
            aepIssueLabel.alpha = 1
        case .success:
            navigationItem.rightBarButtonItem?.isEnabled = true
            aepIssueLabel.alpha = 0
        }
    }

    @objc
    private func didTapNext() {
        switch validateAEPText() {
        case .notFullyEntered, .malformedAEP, .wellFormedButMismatched:
            owsFailDebug("Next button should be disabled!")
        case .success(let aep):
            aepTextView.resignFirstResponder()
            onEntryConfirmed(aep)
        }
    }
}

// MARK: -

#if DEBUG

private extension EnterAccountEntropyPoolViewController {
    static func forPreview() -> EnterAccountEntropyPoolViewController {
        let viewController = EnterAccountEntropyPoolViewController()
        viewController.configure(
            aepValidationPolicy: .acceptAnyWellFormed,
            colorConfig: ColorConfig(
                background: UIColor.Signal.background,
                aepEntryBackground: UIColor.Signal.quaternaryFill,
            ),
            headerStrings: HeaderStrings(
                title: "This is a Title",
                subtitle: "And this, longer, less important string, is a subtitle!"
            ),
            footerButtonConfig: FooterButtonConfig(
                title: "Footer Button",
                action: { print("Footer button!") }
            ),
            onEntryConfirmed: { print("Confirmed: \($0.displayString)") }
        )
        return viewController
    }
}

@available(iOS 17, *)
#Preview {
    return UINavigationController(
        rootViewController: EnterAccountEntropyPoolViewController.forPreview()
    )
}

#endif
