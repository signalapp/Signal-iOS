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

    private lazy var titleLabel: UILabel = {
        let result = UILabel.titleLabelForRegistration(
            text: OWSLocalizedString(
                "ONBOARDING_CHOOSE_RESTORE_METHOD_TITLE",
                comment: "If a user is installing Signal on a new phone, they may be asked whether they want to restore their device from a backup."
            )
        )
        return result
    }()

    private lazy var explanationLabel: UILabel = {
        let result = UILabel.explanationLabelForRegistration(
            text: OWSLocalizedString(
                "ONBOARDING_CHOOSE_RESTORE_METHOD_DESCRIPTION",
                comment: "If a user is installing Signal on a new phone, they may be asked whether they want to restore their device from a backup. This is a description of that question."
            )
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

    private lazy var restoreFromBackupButton = choiceButton(
        title: OWSLocalizedString(
            "ONBOARDING_CHOOSE_RESTORE_METHOD_BACKUPS_TITLE",
            comment: "The title for the device transfer 'choice' view 'transfer' option"
        ),
        body: OWSLocalizedString(
            "ONBOARDING_CHOOSE_RESTORE_METHOD_BACKUPS_BODY",
            comment: "The body for the device transfer 'choice' view 'transfer' option"
        ),
        iconName: Theme.iconName(.backup),
        selector: #selector(didSelectRestoreLocal)
    )

    private lazy var transferButton = choiceButton(
        title: OWSLocalizedString(
            "ONBOARDING_CHOOSE_RESTORE_METHOD_TRANSFER_TITLE",
            comment: "The title for the device transfer 'choice' view 'transfer' option"
        ),
        body: OWSLocalizedString(
            "ONBOARDING_CHOOSE_RESTORE_METHOD_TRANSFER_BODY",
            comment: "The body for the device transfer 'choice' view 'transfer' option"
        ),
        iconName: Theme.iconName(.transfer),
        selector: #selector(didSelectDeviceTransfer)
    )

    private lazy var skipRestoreButton = choiceButton(
        title: OWSLocalizedString(
            "ONBOARDING_CHOOSE_RESTORE_METHOD_SKIP_RESTORE_TITLE",
            comment: "The title for the skip restore 'choice' option"
        ),
        body: OWSLocalizedString(
            "ONBOARDING_CHOOSE_RESTORE_METHOD_SKIP_RESTORE_BODY",
            comment: "The body for the skip restore 'choice' option"
        ),
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

        // TODO: [Backups]: Check for list of available restore options
        // and build list based on that.
        // This should also check if this is a QuickRestore or not
        // to change the position of the 'Skip Restore' button
        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            explanationLabel,
            transferButton,
            restoreFromBackupButton,
            skipRestoreButton,
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

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        render()
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

#if DEBUG
private class PreviewRegistrationChooseRestoreMethodPresenter: RegistrationChooseRestoreMethodPresenter {
    func didChooseRestoreMethod(method: RegistrationRestoreMethod) {
        print("restore method: \(method)")
    }
}

// Need to hold a reference to this since it's held weakly by the VC
private let presenter = PreviewRegistrationChooseRestoreMethodPresenter()
@available(iOS 17, *)
#Preview {
    RegistrationChooseRestoreMethodViewController(presenter: presenter)
}
#endif
