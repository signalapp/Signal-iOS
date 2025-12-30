//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class RegistrationLoadingViewController: OWSViewController, OWSNavigationChildController {
    enum RegistrationLoadingMode {
        case generic
        case submittingPhoneNumber(e164: String)
        case submittingVerificationCode
        case restoringBackup(BackupProgressModal)
    }

    init(mode: RegistrationLoadingMode) {
        spinnerView = AnimatedProgressView(loadingText: {
            switch mode {
            case .generic:
                return ""
            case let .submittingPhoneNumber(e164):
                let format = OWSLocalizedString(
                    "REGISTRATION_VIEW_PHONE_NUMBER_SPINNER_LABEL_FORMAT",
                    comment: "Label for the progress spinner shown during phone number registration. Embeds {{phone number}}.",
                )
                return String(format: format, e164.e164FormattedAsPhoneNumberWithoutBreaks)
            case .submittingVerificationCode:
                return OWSLocalizedString(
                    "ONBOARDING_VERIFICATION_CODE_VALIDATION_PROGRESS_LABEL",
                    comment: "Label for a progress spinner currently validating code",
                )
            case .restoringBackup:
                // TODO: [Backups] localize
                return "Restoring from backup…"
                // comment: "Label for a progress spinner when restoring from backup"
            }
        }())

        super.init()

        navigationItem.hidesBackButton = true
    }

    @available(*, unavailable)
    override init() {
        owsFail("This should not be called")
    }

    // MARK: OWSNavigationChildController

    var preferredNavigationBarStyle: OWSNavigationBarStyle { .solid }

    var navbarBackgroundColorOverride: UIColor? { .clear }

    var prefersNavigationBarHidden: Bool { true }

    // MARK: - Rendering

    private let spinnerView: AnimatedProgressView

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        spinnerView.alpha = 1
        view.addSubview(spinnerView)
        spinnerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            spinnerView.centerXAnchor.constraint(equalTo: contentLayoutGuide.centerXAnchor),
            spinnerView.centerYAnchor.constraint(equalTo: contentLayoutGuide.centerYAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if spinnerView.isAnimating.negated {
            spinnerView.startAnimating()
        }
    }
}
