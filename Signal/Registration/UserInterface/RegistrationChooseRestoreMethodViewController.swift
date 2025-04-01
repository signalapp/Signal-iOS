//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Foundation
import SignalServiceKit
import SignalUI

protocol RegistrationChooseRestoreMethodPresenter: AnyObject {
    func didChooseRestoreMethod(method: RegistrationRestoreMethod)
}

public enum RegistrationRestoreMethod {
    case deviceTransfer
    case local(fileUrl: URL)
    case remote
    case declined
}

class RegistrationChooseRestoreMethodViewController: OWSViewController {

    private weak var presenter: RegistrationChooseRestoreMethodPresenter?

    public init(presenter: RegistrationChooseRestoreMethodPresenter) {
        self.presenter = presenter
        super.init()
    }

    // MARK: Rendering

    // TODO: [Backups] localize
    private lazy var titleLabel: UILabel = {
        let result = UILabel.titleLabelForRegistration(
            text: "Restore from backup"
            // comment: "If a user is installing Signal on a new phone, they may be asked whether they want to restore their device from a backup."
        )
        return result
    }()

    // TODO: [Backups] localize
    private lazy var explanationLabel: UILabel = {
        let result = UILabel.explanationLabelForRegistration(text:
            "Restore message history from a local backup. Only media sent or received in the past 30 days is included."
            // comment: "If a userk is installing Signal on a new phone, they may be asked whether they want to restore their device from a backup. This is a description of that question."
        )
        return result
    }()

    private func choiceButton(
        title: String,
        body: String,
        iconName: String,
        selector: Selector
    ) -> OWSFlatButton {
        let button = RegistrationChoiceButton(title: title, body: body, iconName: iconName)
        button.addTarget(target: self, selector: selector)
        return button
    }

    // TODO: [Backups] localize
    private lazy var restoreFromBackupButton = choiceButton(
        title: "Restore Signal Backup",
        // comment: "The title for the device transfer 'choice' view 'transfer' option"
        body:
            "Restore all your text messages + your last 30 days of media",
        // comment: "The body for the device transfer 'choice' view 'transfer' option"
        iconName: Theme.iconName(.backup),
        selector: #selector(didSelectRestoreLocal)
    )

    // TODO: [Backups] localize
    private lazy var transferButton = choiceButton(
        title: "Transfer from another device",
        // comment: "The title for the device transfer 'choice' view 'transfer' option"
        body: "Transfer directly from an existing device",
        // comment: "The body for the device transfer 'choice' view 'transfer' option"
        iconName: Theme.iconName(.transfer),
        selector: #selector(didSelectDeviceTransfer)
    )

    // TODO: [Backups] localize
    private lazy var continueButton = choiceButton(
        title: "Continue without restoring",
        // comment: "The title for the device transfer 'choice' view 'transfer' option"
        body: "Don't attempt to restore, continue with a new instance.",
        // comment: "The body for the device transfer 'choice' view 'transfer' option"
        iconName: Theme.iconName(.register),
        selector: #selector(didSkipRestore)
    )

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

        let scrollView = UIScrollView()
        view.addSubview(scrollView)
        scrollView.autoPinEdgesToSuperviewMargins()

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            explanationLabel,
            restoreFromBackupButton,
            transferButton,
            continueButton,
            UIView.vStretchingSpacer()
        ])
        stackView.axis = .vertical
        stackView.distribution = .fill
        stackView.spacing = 16
        stackView.setCustomSpacing(12, after: titleLabel)
        stackView.setCustomSpacing(24, after: explanationLabel)
        scrollView.addSubview(stackView)
        stackView.autoPinWidth(toWidthOf: scrollView)
        stackView.autoPinHeightToSuperview()

        render()
    }

    private func render() {
        view.backgroundColor = Theme.backgroundColor
        titleLabel.textColor = .colorForRegistrationTitleLabel
        explanationLabel.textColor = .colorForRegistrationExplanationLabel
    }

    // MARK: Events

    @objc
    private func didSelectRestoreLocal() {
        let actionSheet = ActionSheetController(title: "Choose backup import source:")
        let localFileAction = ActionSheetAction(title: "Local backup") { [weak self] _ in
            self?.showMessageBackupPicker()
        }
        actionSheet.addAction(localFileAction)
        let remoteFileAction = ActionSheetAction(title: "Remote backup") { [weak self] _ in
            self?.presenter?.didChooseRestoreMethod(method: .remote)
        }
        actionSheet.addAction(remoteFileAction)
        presentActionSheet(actionSheet)
    }

    @objc
    private func didSelectDeviceTransfer() {
        presenter?.didChooseRestoreMethod(method: .deviceTransfer)
    }

    @objc
    private func didSkipRestore() {
        presenter?.didChooseRestoreMethod(method: .declined)
    }

    private func showMessageBackupPicker() {
        let vc = UIApplication.shared.frontmostViewController!
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: !Platform.isSimulator)
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false
        vc.present(documentPicker, animated: true)
    }
}

extension RegistrationChooseRestoreMethodViewController: UIDocumentPickerDelegate {
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let fileUrl = urls.first else {
            return
        }
        presenter?.didChooseRestoreMethod(method: .local(fileUrl: fileUrl))
    }
}
