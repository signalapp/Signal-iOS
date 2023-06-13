//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalUI

class RegistrationLoadingViewController: OWSViewController {
    enum RegistrationLoadingMode {
        case generic
        case submittingPhoneNumber(e164: String)
        case submittingVerificationCode
    }

    public init(mode: RegistrationLoadingMode) {
        spinnerView = AnimatedProgressView(loadingText: {
            switch mode {
            case .generic:
                return ""
            case let .submittingPhoneNumber(e164):
                let format = OWSLocalizedString(
                    "REGISTRATION_VIEW_PHONE_NUMBER_SPINNER_LABEL_FORMAT",
                    comment: "Label for the progress spinner shown during phone number registration. Embeds {{phone number}}."
                )
                return String(format: format, e164.e164FormattedAsPhoneNumberWithoutBreaks)
            case .submittingVerificationCode:
                return OWSLocalizedString(
                    "ONBOARDING_VERIFICATION_CODE_VALIDATION_PROGRESS_LABEL",
                    comment: "Label for a progress spinner currently validating code"
                )
            }
        }())

        super.init()
    }

    @available(*, unavailable)
    public override init() {
        owsFail("This should not be called")
    }

    // MARK: - Rendering

    private let spinnerView: AnimatedProgressView

    public override func viewDidLoad() {
        super.viewDidLoad()
        initialRender()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if spinnerView.isAnimating.negated {
            spinnerView.startAnimating()
        }
    }

    public override func themeDidChange() {
        super.themeDidChange()
        render()
    }

    private func initialRender() {
        navigationItem.setHidesBackButton(true, animated: false)

        spinnerView.alpha = 1

        view.addSubview(spinnerView)
        spinnerView.autoCenterInSuperviewMargins()

        render()
    }

    private func render() {
        view.backgroundColor = Theme.backgroundColor
    }
}
