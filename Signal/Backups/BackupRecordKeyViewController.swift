//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

class BackupRecordKeyViewController: OWSViewController, OWSNavigationChildController {
    struct Option: OptionSet {
        let rawValue: Int

        /// Show a "continue" button in the view footer. Not compatible with
        /// `.showCreateNewKeyButton`.
        static let showContinueButton = Option(rawValue: 1 << 1)
        /// Show a "create new key" button in the view footer. Not compatible
        /// with `.showContinueButton`.
        static let showCreateNewKeyButton = Option(rawValue: 1 << 2)
    }

    enum AEPMode {
        /// The user's current AEP, which must only be viewed after device auth.
        case current(AccountEntropyPool, LocalDeviceAuthentication.AuthSuccess)
        /// A new candidate AEP.
        case newCandidate(AccountEntropyPool)

        fileprivate var aep: AccountEntropyPool {
            switch self {
            case .current(let aep, _): return aep
            case .newCandidate(let aep): return aep
            }
        }
    }

    private let aep: AccountEntropyPool
    private let onContinuePressedBlock: (BackupRecordKeyViewController) -> Void
    private let onCreateNewKeyPressedBlock: (BackupRecordKeyViewController) -> Void
    private let options: [Option]

    /// - Parameter onCreateNewKeyPressed
    /// Called when the user taps the "create new key" button. Only relevant if
    /// the `.showCreateNewKeyButton` option is passed.
    /// - Parameter onContinuePressed
    /// Called when the user taps the "continue" button. Only relevant if the
    /// `.showContinueButton` option is passed.
    init(
        aepMode: AEPMode,
        options: [Option],
        onCreateNewKeyPressed: @escaping (BackupRecordKeyViewController) -> Void = { _ in },
        onContinuePressed: @escaping (BackupRecordKeyViewController) -> Void = { _ in },
    ) {
        self.aep = aepMode.aep
        self.onContinuePressedBlock = onContinuePressed
        self.onCreateNewKeyPressedBlock = onCreateNewKeyPressed
        self.options = options

        super.init()

        OWSTableViewController2.removeBackButtonText(viewController: self)
    }

    var navbarBackgroundColorOverride: UIColor? {
        .Signal.groupedBackground
    }

    // MARK: -

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.groupedBackground

        let heroIconView = UIImageView()
        heroIconView.image = .backupsLock
        heroIconView.contentMode = .center
        heroIconView.autoSetDimensions(to: .square(80))

        let headlineLabel = UILabel()
        headlineLabel.text = OWSLocalizedString(
            "BACKUP_RECORD_KEY_TITLE",
            comment: "Title for a view allowing users to record their 'Recovery Key'."
        )
        headlineLabel.font = .dynamicTypeTitle1.semibold()
        headlineLabel.textColor = .Signal.label
        headlineLabel.numberOfLines = 0
        headlineLabel.textAlignment = .center

        let subheadlineLabel = UILabel()
        subheadlineLabel.text = OWSLocalizedString(
            "BACKUP_RECORD_KEY_SUBTITLE",
            comment: "Subtitle for a view allowing users to record their 'Recovery Key'."
        )
        subheadlineLabel.font = .dynamicTypeBody
        subheadlineLabel.textColor = .Signal.secondaryLabel
        subheadlineLabel.numberOfLines = 0
        subheadlineLabel.textAlignment = .center

        let aepTextView = AccountEntropyPoolTextView(mode: .display(aep: aep))
        aepTextView.backgroundColor = .Signal.secondaryGroupedBackground

        let copyToClipboardButton = UIButton(
            configuration: {
                var configuration: UIButton.Configuration = .plain()
                configuration.attributedTitle = AttributedString(
                    OWSLocalizedString(
                        "BACKUP_RECORD_KEY_COPY_TO_CLIPBOARD_BUTTON_TITLE",
                        comment: "Title for a button allowing users to copy their 'Recovery Key' to the clipboard."
                    ),
                    attributes: AttributeContainer([
                        .font: UIFont.dynamicTypeFootnote.medium(),
                        .foregroundColor: UIColor.Signal.label,
                    ])
                )
                configuration.background.backgroundColor = .Signal.secondaryFill
                configuration.cornerStyle = .capsule
                configuration.contentInsets = .init(hMargin: 12, vMargin: 8)
                return configuration
            }(),
            primaryAction: UIAction { [weak self] _ in
                self?.copyToClipboard()
            }
        )

        let createNewKeyButton = UIButton(
            configuration: {
                var configuration: UIButton.Configuration = .plain()
                configuration.attributedTitle = AttributedString(
                    OWSLocalizedString(
                        "BACKUP_RECORD_KEY_CREATE_NEW_KEY_BUTTON_TITLE",
                        comment: "Title for a button allowing users to create a new 'Recovery Key'."
                    ),
                    attributes: AttributeContainer([
                        .font: UIFont.dynamicTypeHeadline,
                        .foregroundColor: UIColor.Signal.accent,

                    ])
                )
                return configuration
            }(),
            primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                onCreateNewKeyPressedBlock(self)
            },
        )

        let continueButton = UIButton(
            configuration: {
                var configuration: UIButton.Configuration = .plain()
                configuration.attributedTitle = AttributedString(
                    OWSLocalizedString(
                        "BACKUP_RECORD_KEY_CREATE_NEW_KEY_BUTTON_TITLE",
                        comment: "Title for a button allowing users to create a new 'Recovery Key'."
                    ),
                    attributes: AttributeContainer([
                        .font: UIFont.dynamicTypeHeadline,
                        .foregroundColor: UIColor.white,
                    ])
                )
                configuration.contentInsets = .init(hMargin: 0, vMargin: 14)
                configuration.background.cornerRadius = 12
                configuration.background.backgroundColor = .Signal.accent
                return configuration
            }(),
            primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                onCreateNewKeyPressedBlock(self)
            },
        )

        let bottomButtonSpacer = UIView(forAutoLayout: ())
        bottomButtonSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)

        let scrollView = UIScrollView()
        self.view.addSubview(scrollView)
        scrollView.autoPinEdgesToSuperviewEdges()

        let stackView = UIStackView(arrangedSubviews: [
            heroIconView,
            headlineLabel,
            subheadlineLabel,
            aepTextView,
            copyToClipboardButton,
            bottomButtonSpacer,
        ])
        if options.contains(.showCreateNewKeyButton) {
            stackView.addArrangedSubview(createNewKeyButton)
        }
        if options.contains(.showContinueButton) {
            stackView.addArrangedSubview(continueButton)
        }

        scrollView.addSubview(stackView)
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 24
        stackView.setCustomSpacing(32, after: aepTextView)

        headlineLabel.autoPinEdge(toSuperviewEdge: .leading, withInset: 8)
        headlineLabel.autoPinEdge(toSuperviewEdge: .trailing, withInset: 8)

        subheadlineLabel.autoPinEdge(toSuperviewEdge: .leading, withInset: 24)
        subheadlineLabel.autoPinEdge(toSuperviewEdge: .trailing, withInset: 24)

        let topInset: CGFloat = 20
        let bottomInset: CGFloat = 16
        stackView.autoPinEdge(.leading, to: .leading, of: view, withOffset: 24)
        stackView.autoPinEdge(.trailing, to: .trailing, of: view, withOffset: -24)
        stackView.autoPinEdge(toSuperviewEdge: .top, withInset: topInset)
        stackView.autoPinEdge(toSuperviewEdge: .bottom, withInset: bottomInset)
        NSLayoutConstraint.activate([
            stackView.heightAnchor.constraint(
                greaterThanOrEqualTo: view.safeAreaLayoutGuide.heightAnchor,
                constant: -(topInset + bottomInset),
            )
        ])

        /*
        bottomButtonSpacer.backgroundColor = .brown
        bottomButtonSpacer.widthAnchor.constraint(equalToConstant: 10).isActive = true
        stackView.backgroundColor = .green
        scrollView.backgroundColor = .orange
         */
    }

    private func copyToClipboard() {
        UIPasteboard.general.setItems(
            [[UIPasteboard.typeAutomatic: aep.displayString]],
            options: [.expirationDate: Date().addingTimeInterval(60)]
        )

        let toast = ToastController(text: OWSLocalizedString(
            "BACKUP_KEY_COPIED_MESSAGE_TOAST",
            comment: "Toast indicating that the user has copied their recovery key."
        ))
        toast.presentToastView(from: .bottom, of: view, inset: view.safeAreaInsets.bottom + 8)
    }
}

// MARK: -

#if DEBUG

private extension BackupRecordKeyViewController {
    static func forPreview(
        aepMode: AEPMode,
        options: [Option],
    ) -> BackupRecordKeyViewController {
        return BackupRecordKeyViewController(
            aepMode: aepMode,
            options: options,
            onCreateNewKeyPressed: { _ in print("Create New Key!") },
            onContinuePressed: { _ in print("Continue!") },
        )
    }
}

@available(iOS 17, *)
#Preview("CreateNewKey") {
    UINavigationController(rootViewController: BackupRecordKeyViewController.forPreview(
        aepMode: .newCandidate(AccountEntropyPool()),
        options: [.showCreateNewKeyButton]
    ))
}

@available(iOS 17, *)
#Preview("ContinueButton") {
    UINavigationController(rootViewController: BackupRecordKeyViewController.forPreview(
        aepMode: .newCandidate(AccountEntropyPool()),
        options: [.showContinueButton]
    ))
}

#endif
