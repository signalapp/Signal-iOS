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

    var shouldCancelNavigationBack: Bool {
        onBackPressedBlock != nil
    }

    private let aep: AccountEntropyPool
    private let onContinuePressedBlock: (BackupRecordKeyViewController) -> Void
    private let onCreateNewKeyPressedBlock: (BackupRecordKeyViewController) -> Void
    private let onBackPressedBlock: (() -> Void)?
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
        onBackPressed: (() -> Void)? = nil,
    ) {
        self.aep = aepMode.aep
        self.onContinuePressedBlock = onContinuePressed
        self.onCreateNewKeyPressedBlock = onCreateNewKeyPressed
        self.onBackPressedBlock = onBackPressed
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

        if let onBackPressedBlock {
            navigationItem.hidesBackButton = true
            navigationItem.leftBarButtonItem = .init(
                image: UIImage(named: "chevron-left-bold-28"),
                primaryAction: UIAction { _ in
                    onBackPressedBlock()
                },
            )

            isModalInPresentation = true
        }

        let heroIconView = UIImageView()
        heroIconView.image = .backupsLock
        heroIconView.contentMode = .scaleAspectFit

        let headlineLabel = UILabel.title1Label(text: OWSLocalizedString(
            "BACKUP_RECORD_KEY_TITLE",
            comment: "Title for a view allowing users to record their 'Recovery Key'.",
        ))

        let subheadlineLabel = UILabel.explanationTextLabel(text: OWSLocalizedString(
            "BACKUP_RECORD_KEY_SUBTITLE",
            comment: "Subtitle for a view allowing users to record their 'Recovery Key'.",
        ))

        let aepTextView = AccountEntropyPoolTextView(mode: .display(aep: aep))
        aepTextView.backgroundColor = .Signal.secondaryGroupedBackground

        let copyToClipboardButton = UIButton(
            configuration: .smallSecondary(title: OWSLocalizedString(
                "BACKUP_RECORD_KEY_COPY_TO_CLIPBOARD_BUTTON_TITLE",
                comment: "Title for a button allowing users to copy their 'Recovery Key' to the clipboard.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.copyToClipboard()
            },
        )
        copyToClipboardButton.translatesAutoresizingMaskIntoConstraints = false
        let copyButtonContainer = UIView.container()
        copyButtonContainer.addSubview(copyToClipboardButton)
        copyButtonContainer.addConstraints([
            copyToClipboardButton.topAnchor.constraint(equalTo: copyButtonContainer.topAnchor),
            copyToClipboardButton.leadingAnchor.constraint(greaterThanOrEqualTo: copyToClipboardButton.leadingAnchor),
            copyToClipboardButton.centerXAnchor.constraint(equalTo: copyButtonContainer.centerXAnchor),
            copyToClipboardButton.bottomAnchor.constraint(equalTo: copyButtonContainer.bottomAnchor),
        ])

        let createNewKeyButton = UIButton(
            configuration: .largeSecondary(title: OWSLocalizedString(
                "BACKUP_RECORD_KEY_CREATE_NEW_KEY_BUTTON_TITLE",
                comment: "Title for a button allowing users to create a new 'Recovery Key'.",
            )),
            primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                onCreateNewKeyPressedBlock(self)
            },
        )

        let continueButton = UIButton(
            configuration: .largePrimary(title: CommonStrings.continueButton),
            primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                onContinuePressedBlock(self)
            },
        )

        let stackView = addStaticContentStackView(
            arrangedSubviews: [
                heroIconView,
                headlineLabel,
                subheadlineLabel,
                aepTextView,
                copyButtonContainer,
                .vStretchingSpacer(),
            ],
            isScrollable: true,
        )
        stackView.spacing = 24
        stackView.setCustomSpacing(32, after: aepTextView)

        var bottomButtons = [UIButton]()
        if options.contains(.showCreateNewKeyButton) {
            bottomButtons.append(createNewKeyButton)
        }
        if options.contains(.showContinueButton) {
            bottomButtons.append(continueButton)
        }
        if !bottomButtons.isEmpty {
            stackView.addArrangedSubview(bottomButtons.enclosedInVerticalStackView(isFullWidthButtons: options.contains(.showContinueButton)))
        }
    }

    private func copyToClipboard() {
        UIPasteboard.general.setItems(
            [[UIPasteboard.typeAutomatic: aep.displayString]],
            options: [.expirationDate: Date().addingTimeInterval(60)],
        )

        let toast = ToastController(text: OWSLocalizedString(
            "BACKUP_KEY_COPIED_MESSAGE_TOAST",
            comment: "Toast indicating that the user has copied their recovery key.",
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
        options: [.showCreateNewKeyButton],
    ))
}

@available(iOS 17, *)
#Preview("ContinueButton") {
    UINavigationController(rootViewController: BackupRecordKeyViewController.forPreview(
        aepMode: .newCandidate(AccountEntropyPool()),
        options: [.showContinueButton],
    ))
}

#endif
