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

class RegistrationChooseRestoreMethodViewController: OWSViewController {

    private weak var presenter: RegistrationChooseRestoreMethodPresenter?
    private let restorePath: RegistrationStep.RestorePath

    public init(
        presenter: RegistrationChooseRestoreMethodPresenter,
        restorePath: RegistrationStep.RestorePath
    ) {
        self.presenter = presenter
        self.restorePath = restorePath
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
        iconSize: CGFloat? = nil,
        selector: Selector
    ) -> OWSFlatButton {
        let button = RegistrationChoiceButton(title: title, body: body, iconName: iconName, iconSize: iconSize)
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
        iconName: "backup-light",
        iconSize: 32,
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

    private lazy var prominentSkipRestoreButton = choiceButton(
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

    private lazy var smallSkipRestoreButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = OWSLocalizedString(
            "ONBOARDING_CHOOSE_RESTORE_METHOD_SKIP_RESTORE_SMALL_TITLE",
            comment: "The title for a less-prominent skip restore 'choice' option"
        )
        config.baseForegroundColor = UIColor.Signal.accent
        config.titleTextAttributesTransformer = .defaultFont(.dynamicTypeBody.semibold())
        return UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            self?.didSkipRestore()
        })
    }()

    private lazy var cancelButton = OWSFlatButton.secondaryButtonForRegistration(
        title: CommonStrings.cancelButton,
        target: self,
        selector: #selector(didTapCancel)
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
        scrollView.autoPinEdgesToSuperviewEdges()

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            explanationLabel,
        ])
        switch self.restorePath {
        case .quickRestore:
            stackView.addArrangedSubviews([
                restoreFromBackupButton,
                transferButton,
            ])

            view.addSubview(smallSkipRestoreButton)
            smallSkipRestoreButton.autoHCenterInSuperview()
            smallSkipRestoreButton.autoPinBottomToSuperviewMargin(withInset: 14)
        case .manualRestore:
            stackView.addArrangedSubviews([
                restoreFromBackupButton,
                prominentSkipRestoreButton,
            ])
            view.addSubview(cancelButton)
            cancelButton.autoHCenterInSuperview()
            cancelButton.autoPinBottomToSuperviewMargin(withInset: 14)
        case .unspecified:
            stackView.addArrangedSubviews([
                transferButton,
                restoreFromBackupButton,
                prominentSkipRestoreButton,
            ])
        }
        stackView.addArrangedSubviews([])
        stackView.axis = .vertical
        stackView.distribution = .fill
        stackView.spacing = 16
        stackView.layoutMargins = .init(hMargin: 20, vMargin: 0)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.setCustomSpacing(12, after: titleLabel)
        stackView.setCustomSpacing(24, after: explanationLabel)
        scrollView.addSubview(stackView)
        stackView.autoPinWidth(toWidthOf: scrollView)

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

    @objc
    private func didTapCancel() {
        presenter?.didCancelRestoreMethodSelection()
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

    func didCancelRestoreMethodSelection() {
        print("did cancel")
    }
}

// Need to hold a reference to this since it's held weakly by the VC
private let presenter = PreviewRegistrationChooseRestoreMethodPresenter()

@available(iOS 17, *)
#Preview("Quick Restore") {
    OWSNavigationController(
        rootViewController: RegistrationChooseRestoreMethodViewController(
            presenter: presenter,
            restorePath: .quickRestore,
        )
    )
}

@available(iOS 17, *)
#Preview("Manual Restore") {
    OWSNavigationController(
        rootViewController: RegistrationChooseRestoreMethodViewController(
            presenter: presenter,
            restorePath: .manualRestore,
        )
    )
}

@available(iOS 17, *)
#Preview("Unspecified") {
    OWSNavigationController(
        rootViewController: RegistrationChooseRestoreMethodViewController(
            presenter: presenter,
            restorePath: .unspecified,
        )
    )
}
#endif
