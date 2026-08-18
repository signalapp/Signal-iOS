//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Foundation
import SignalServiceKit
import SignalUI

protocol RegistrationChooseRestoreMethodPresenter: AnyObject {
    func didChooseRestoreMethod(method: RegistrationRestoreMethod)
    func didCancelRestoreMethodSelection()
}

public enum RegistrationRestoreMethod {
    case deviceTransfer
    case local(fileUrl: URL)
    case remote
    case declined
}

class RegistrationChooseRestoreMethodViewController: OWSViewController, UIDocumentPickerDelegate {

    private weak var presenter: RegistrationChooseRestoreMethodPresenter?
    private let restorePath: RegistrationStep.RestorePath
    private let securityScopedBookmarkAccess: SecurityScopedBookmarkAccess

    init(
        presenter: RegistrationChooseRestoreMethodPresenter,
        restorePath: RegistrationStep.RestorePath,
        securityScopedBookmarkAccess: SecurityScopedBookmarkAccess,
    ) {
        self.presenter = presenter
        self.restorePath = restorePath
        self.securityScopedBookmarkAccess = securityScopedBookmarkAccess

        super.init()

        navigationItem.hidesBackButton = true
    }

    // MARK: UI

    private func localFileBackupRestoreButton() -> UIButton {
        return UIButton.registrationChoiceButton(
            title: "(DEV ONLY) Restore from local backup",
            subtitle: "(DEV ONLY) restore from local backup",
            iconName: "signal-backups-48",
            primaryAction: UIAction { [weak self] _ in
                self?.didSelectRestoreFromLocalBackup()
            },
        )
    }

    private func prominentRestoreButton() -> UIButton {
        return UIButton.registrationChoiceButton(
            title: OWSLocalizedString(
                "ONBOARDING_CHOOSE_RESTORE_METHOD_BACKUPS_TITLE",
                comment: "The title for the device transfer 'choice' view 'restore backup' option",
            ),
            subtitle: OWSLocalizedString(
                "ONBOARDING_CHOOSE_RESTORE_METHOD_BACKUPS_BODY",
                comment: "The body for the device transfer 'choice' view 'restore backup' option",
            ),
            iconName: "signal-backups-48",
            primaryAction: UIAction { [weak self] _ in
                self?.didSelectRestoreFromBackup()
            },
        )
    }

    private func prominentTransferButton() -> UIButton {
        return UIButton.registrationChoiceButton(
            title: OWSLocalizedString(
                "ONBOARDING_CHOOSE_RESTORE_METHOD_TRANSFER_TITLE",
                comment: "The title for the device transfer 'choice' view 'transfer' option",
            ),
            subtitle: OWSLocalizedString(
                "ONBOARDING_CHOOSE_RESTORE_METHOD_TRANSFER_BODY",
                comment: "The body for the device transfer 'choice' view 'transfer' option",
            ),
            iconName: "transfer-48",
            primaryAction: UIAction { [weak self] _ in
                self?.didSelectDeviceTransfer()
            },
        )
    }

    private func prominentSkipRestoreButton() -> UIButton {
        return UIButton.registrationChoiceButton(
            title: OWSLocalizedString(
                "ONBOARDING_CHOOSE_RESTORE_METHOD_SKIP_RESTORE_TITLE",
                comment: "The title for the skip restore 'choice' option",
            ),
            subtitle: OWSLocalizedString(
                "ONBOARDING_CHOOSE_RESTORE_METHOD_SKIP_RESTORE_BODY",
                comment: "The body for the skip restore 'choice' option",
            ),
            iconName: "continue-48",
            primaryAction: UIAction { [weak self] _ in
                self?.didSkipRestore()
            },
        )
    }

    private func skipRestoreButton(isLargeButton: Bool) -> UIButton {
        let buttonTitle = OWSLocalizedString(
            "ONBOARDING_CHOOSE_RESTORE_METHOD_SKIP_RESTORE_SMALL_TITLE",
            comment: "The title for a less-prominent skip restore 'choice' option",
        )
        let buttonConfiguration: UIButton.Configuration
        if isLargeButton {
            buttonConfiguration = .largeSecondary(title: buttonTitle)
        } else {
            buttonConfiguration = .mediumSecondary(title: buttonTitle)
        }
        return UIButton(
            configuration: buttonConfiguration,
            primaryAction: UIAction { [weak self] _ in
                self?.didSkipRestore()
            },
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        // Content view.
        let stackView = addStaticContentStackView(arrangedSubviews: [], isScrollable: true)
        switch self.restorePath {
        case .quickRestore(let tier, let platform) where platform == .android:
            switch tier {
            case .free, .paid:
                addDefaultTitle(to: stackView)
                stackView.addArrangedSubviews([
                    prominentRestoreButton(),
                    prominentSkipRestoreButton(),
                    .vStretchingSpacer(),
                ])
            case .none:
                addNoRestoreOptionViews(to: stackView)
            }
        case .quickRestore(let tier, _):
            addDefaultTitle(to: stackView)
            switch tier {
            case .free:
                let bottomButton = skipRestoreButton(isLargeButton: false)
                stackView.addArrangedSubviews([
                    prominentTransferButton(),
                    prominentRestoreButton(),
                    .vStretchingSpacer(),
                    bottomButton.enclosedInVerticalStackView(isFullWidthButton: false),
                ])

            case .paid:
                let bottomButton = skipRestoreButton(isLargeButton: false)
                stackView.addArrangedSubviews([
                    prominentRestoreButton(),
                    prominentTransferButton(),
                    .vStretchingSpacer(),
                    bottomButton.enclosedInVerticalStackView(isFullWidthButton: false),
                ])

            case .none:
                stackView.addArrangedSubviews([
                    prominentTransferButton(),
                    prominentSkipRestoreButton(),
                    .vStretchingSpacer(),
                ])
            }
        case .manualRestore:
            addDefaultTitle(to: stackView)
            let bottomButton = UIButton(
                configuration: .mediumSecondary(title: CommonStrings.cancelButton),
                primaryAction: UIAction { [weak self] _ in
                    self?.didTapCancel()
                },
            )
            stackView.addArrangedSubviews([
                prominentRestoreButton(),
                prominentSkipRestoreButton(),
                .vStretchingSpacer(),
                bottomButton.enclosedInVerticalStackView(isFullWidthButton: false),
            ])

            if BuildFlags.LocalFileBackups.restore {
                stackView.addArrangedSubview(localFileBackupRestoreButton())
            }
        case .unspecified:
            addDefaultTitle(to: stackView)
            stackView.addArrangedSubviews([
                prominentTransferButton(),
                prominentRestoreButton(),
                prominentSkipRestoreButton(),
                .vStretchingSpacer(),
            ])

            if BuildFlags.LocalFileBackups.restore {
                stackView.addArrangedSubview(localFileBackupRestoreButton())
            }
        }
    }

    private func addDefaultTitle(to stackView: UIStackView) {
        let titleLabel = UILabel.titleLabelForRegistration(
            text: OWSLocalizedString(
                "ONBOARDING_CHOOSE_RESTORE_METHOD_TITLE",
                comment: "If a user is installing Signal on a new phone, they may be asked whether they want to restore their device from a backup.",
            ),
        )
        let explanationLabel = UILabel.explanationLabelForRegistration(
            text: OWSLocalizedString(
                "ONBOARDING_CHOOSE_RESTORE_METHOD_DESCRIPTION",
                comment: "If a user is installing Signal on a new phone, they may be asked whether they want to restore their device from a backup. This is a description of that question.",
            ),
        )
        stackView.addArrangedSubviews([
            titleLabel,
            explanationLabel,
        ])
        stackView.setCustomSpacing(24, after: explanationLabel)
    }

    private func addNoRestoreOptionViews(to stackView: UIStackView) {
        let title = UILabel.titleLabelForRegistration(
            text: OWSLocalizedString(
                "ONBOARDING_CHOOSE_RESTORE_METHOD_NONE_AVAILABLE_TITLE",
                comment: "Title displayed to a user during registration if there are no restore options available.",
            ),
        )
        let body = UILabel.explanationLabelForRegistration(
            text: OWSLocalizedString(
                "ONBOARDING_CHOOSE_RESTORE_METHOD_NONE_AVAILABLE_BODY",
                comment: "Message body displayed to a user during registration if there are no restore options available.",
            ),
        )
        stackView.addArrangedSubviews([
            title,
            body,
        ])
        stackView.setCustomSpacing(32, after: body)

        func labelWithImage(imageName: String, text: String) -> UIView {
            let image = UIImageView(image: UIImage(named: imageName)?.withRenderingMode(.alwaysTemplate))
            image.tintColor = .Signal.secondaryLabel
            let label = UILabel.explanationLabelForRegistration(text: text)
            label.textAlignment = .natural
            let stackView = UIStackView(
                arrangedSubviews: [
                    image,
                    label,
                    SpacerView(),
                ],
            )
            stackView.axis = .horizontal
            stackView.alignment = .firstBaseline
            stackView.isLayoutMarginsRelativeArrangement = true
            stackView.spacing = 16
            stackView.directionalLayoutMargins = .init(top: 6, leading: 30, bottom: 6, trailing: 30)
            return stackView
        }

        stackView.addArrangedSubviews([
            labelWithImage(imageName: "device-phone", text: OWSLocalizedString(
                "REGISTRATION_RESTORE_METHOD_MAKE_BACKUP_TUTORIAL_OPEN_SIGNAL",
                comment: "First step in directions for how to make a backup",
            )),
            labelWithImage(imageName: "backup", text: OWSLocalizedString(
                "REGISTRATION_RESTORE_METHOD_MAKE_BACKUP_TUTORIAL_TAP_SETTINGS",
                comment: "Second step in directions for how to make a backup",
            )),
            labelWithImage(imageName: "check-circle", text: OWSLocalizedString(
                "REGISTRATION_RESTORE_METHOD_MAKE_BACKUP_TUTORIAL_ENABLE_BACKUPS",
                comment: "Third step in directions for how to make a backup",
            )),
        ])

        // Show large "No backup to restore" and "Skip Restore"
        let continueButton = UIButton(
            configuration: .largePrimary(title: CommonStrings.okayButton),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapCancel()
            },
        )
        let skipRestoreButton = skipRestoreButton(isLargeButton: true)

        stackView.addArrangedSubviews([
            .vStretchingSpacer(),
            [continueButton, skipRestoreButton].enclosedInVerticalStackView(isFullWidthButtons: true),
        ])
    }

    // MARK: Events

    private func didSelectRestoreFromBackup() {
        presenter?.didChooseRestoreMethod(method: .remote)
    }

    private func didSelectDeviceTransfer() {
        presenter?.didChooseRestoreMethod(method: .deviceTransfer)
    }

    private func didSkipRestore() {
        // Add a bit of friction by having the user confirm they want to skip restoring.
        var actions = [ActionSheetAction]()
        let title = OWSLocalizedString(
            "ONBOARDING_CHOOSE_RESTORE_METHOD_CONFIRM_SKIP_RESTORE_TITLE",
            comment: "Title for a sheet warning users about skipping restore.",
        )
        let message = OWSLocalizedString(
            "ONBOARDING_CHOOSE_RESTORE_METHOD_CONFIRM_SKIP_RESTORE_BODY",
            comment: "Body for a sheet warning users about skipping restore.",
        )
        let actionTitle = OWSLocalizedString(
            "REGISTRATION_BACKUP_RESTORE_ERROR_SKIP_RESTORE_ACTION",
            comment: "Skip restore action label for backup restore error recovery.",
        )
        actions.append(ActionSheetAction(title: actionTitle) { [weak self] _ in
            self?.presenter?.didChooseRestoreMethod(method: .declined)
        })
        actions.append(ActionSheetAction.cancel)
        let actionSheet = ActionSheetController(title: title, message: message)
        actions.forEach { actionSheet.addAction($0) }
        OWSActionSheets.showActionSheet(actionSheet, fromViewController: self)
    }

    private func didTapCancel() {
        presenter?.didCancelRestoreMethodSelection()
    }

    // MARK: - Local File Backups

    private func didSelectRestoreFromLocalBackup() {
        let heroSheet = LocalFileBackupSelectHeroSheet(onChooseBackup: { [weak self] in
            guard let self else { return }
            promptUserToChooseFileLocationForRestoring(fromViewController: self)
        })
        present(heroSheet, animated: true)
    }

    // MARK: - Choosing backup location

    func promptUserToChooseFileLocationForRestoring(fromViewController: UIViewController) {
        let pickerController = UIDocumentPickerViewController(
            forOpeningContentTypes: [.folder],
            asCopy: false,
        )
        pickerController.delegate = self
        fromViewController.present(pickerController, animated: true)
    }

    // MARK: - UIDocumentPickerDelegate

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        let localFileBackupManager = DependenciesBridge.shared.localFileBackupManager

        // The bookmark data has to be written when we have access to the security scoped resource.
        guard securityScopedBookmarkAccess.startAccessToSecurityScopedBookmark(url: url) else {
            Logger.error("Failed to start security scoped access")
            return
        }

        defer { securityScopedBookmarkAccess.stopAccessToSecurityScopedBookmark(url: url) }

        var contents: [URL] = []
        var signalBackupsURL = url
        do {
            // First, if the user picked the directory above SignalBackups,
            // thats fine, just find it and update the url.
            if url.lastPathComponent != "SignalBackups" {
                contents = try FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey],
                )

                let signalBackupsDir = contents
                    .filter { $0.lastPathComponent == "SignalBackups" }

                guard !signalBackupsDir.isEmpty else {
                    // Its not SignalBackups, and its not the directory above SignalBackups, show an error.
                    presentNoLocalBackupFoundActionSheet()
                    return
                }
                signalBackupsURL = signalBackupsDir.first!
            }

            // Now that we are inside of SignalBackups, we expect a files/ dir
            // and a signal-backups-*/ dir. If either is missing, show an error.
            contents = try FileManager.default.contentsOfDirectory(
                at: signalBackupsURL,
                includingPropertiesForKeys: [.isDirectoryKey],
            )
        } catch {
            Logger.error("Failed to read contents of local backup directory")
            return
        }
        let backupDirectories = contents
            .filter { $0.lastPathComponent.hasPrefix("signal-backups-") }

        let files = contents
            .filter { $0.lastPathComponent == "files" }

        guard !backupDirectories.isEmpty, !files.isEmpty else {
            presentNoLocalBackupFoundActionSheet()
            return
        }

        do {
            try localFileBackupManager.saveSecurityScopedBookmark(url: signalBackupsURL, type: .restore)
            presenter?.didChooseRestoreMethod(method: .local(fileUrl: signalBackupsURL))
        } catch {
            // TODO: [KC] show error screen.
            Logger.error("Failed to save bookmark: \(error)")
        }
    }

    func presentNoLocalBackupFoundActionSheet() {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "LOCAL_BACKUPS_MISSING_BACKUP_ACTION_SHEET_TITLE",
                comment: "Title for an error sheet shown when the user's folder choice does not contain a backup file.",
            ),
            message: OWSLocalizedString(
                "LOCAL_BACKUPS_MISSING_BACKUP_ACTION_SHEET_BODY",
                comment: "Body for an error sheet shown when the user's folder choice does not contain a backup file.",
            ),
        )
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "LOCAL_BACKUPS_MISSING_BACKUP_TRY_DIFFERENT_FOLDER",
                comment: "Title for a button that lets the user select a new folder.",
            ),
            handler: { [self] _ in
                promptUserToChooseFileLocationForRestoring(fromViewController: self)
            },
        ))
        actionSheet.addAction(.cancel)
        present(actionSheet, animated: true)
    }
}

#if DEBUG
private class PreviewRegistrationChooseRestoreMethodPresenter: RegistrationChooseRestoreMethodPresenter {
    func didChooseRestoreMethod(method: RegistrationRestoreMethod) {
        print("restore method: \(method)")
    }

    func didCancelRestoreMethodSelection() {
        print("did cancel")
    }
}

// Need to hold a reference to this since it's held weakly by the VC
private let presenter = PreviewRegistrationChooseRestoreMethodPresenter()

@available(iOS 17, *)
#Preview("Quick Restore iOS free") {
    OWSNavigationController(
        rootViewController: RegistrationChooseRestoreMethodViewController(
            presenter: presenter,
            restorePath: .quickRestore(.free, .ios),
            securityScopedBookmarkAccess: SecurityScopedBookmarkAccessMock(hasAccess: true, url: nil),
        ),
    )
}

@available(iOS 17, *)
#Preview("Quick Restore iOS paid") {
    OWSNavigationController(
        rootViewController: RegistrationChooseRestoreMethodViewController(
            presenter: presenter,
            restorePath: .quickRestore(.paid, .ios),
            securityScopedBookmarkAccess: SecurityScopedBookmarkAccessMock(hasAccess: true, url: nil),
        ),
    )
}

@available(iOS 17, *)
#Preview("Quick Restore iOS no backups") {
    OWSNavigationController(
        rootViewController: RegistrationChooseRestoreMethodViewController(
            presenter: presenter,
            restorePath: .quickRestore(nil, .ios),
            securityScopedBookmarkAccess: SecurityScopedBookmarkAccessMock(hasAccess: true, url: nil),
        ),
    )
}

@available(iOS 17, *)
#Preview("Quick Restore Android source, free") {
    OWSNavigationController(
        rootViewController: RegistrationChooseRestoreMethodViewController(
            presenter: presenter,
            restorePath: .quickRestore(.free, .android),
            securityScopedBookmarkAccess: SecurityScopedBookmarkAccessMock(hasAccess: true, url: nil),
        ),
    )
}

@available(iOS 17, *)
#Preview("Quick Restore Android source, paid") {
    OWSNavigationController(
        rootViewController: RegistrationChooseRestoreMethodViewController(
            presenter: presenter,
            restorePath: .quickRestore(.paid, .android),
            securityScopedBookmarkAccess: SecurityScopedBookmarkAccessMock(hasAccess: true, url: nil),
        ),
    )
}

@available(iOS 17, *)
#Preview("Quick Restore Android source, no backup") {
    OWSNavigationController(
        rootViewController: RegistrationChooseRestoreMethodViewController(
            presenter: presenter,
            restorePath: .quickRestore(nil, .android),
            securityScopedBookmarkAccess: SecurityScopedBookmarkAccessMock(hasAccess: true, url: nil),
        ),
    )
}

@available(iOS 17, *)
#Preview("Manual Restore") {
    OWSNavigationController(
        rootViewController: RegistrationChooseRestoreMethodViewController(
            presenter: presenter,
            restorePath: .manualRestore,
            securityScopedBookmarkAccess: SecurityScopedBookmarkAccessMock(hasAccess: true, url: nil),
        ),
    )
}

@available(iOS 17, *)
#Preview("Unspecified") {
    OWSNavigationController(
        rootViewController: RegistrationChooseRestoreMethodViewController(
            presenter: presenter,
            restorePath: .unspecified,
            securityScopedBookmarkAccess: SecurityScopedBookmarkAccessMock(hasAccess: true, url: nil),
        ),
    )
}
#endif
