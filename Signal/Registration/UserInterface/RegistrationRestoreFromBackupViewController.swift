//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Foundation
import SignalServiceKit
import SignalUI

protocol RegistrationRestoreFromBackupPresenter: AnyObject {
    func didSelectBackup(type: RegistrationMessageBackupRestoreType)
    func skipRestoreFromBackup()
}

public enum RegistrationMessageBackupRestoreType {
    case local(fileUrl: URL)
    case remote
}

class RegistrationRestoreFromBackupViewController: OWSViewController {

    private weak var presenter: RegistrationRestoreFromBackupPresenter?

    public init(presenter: RegistrationRestoreFromBackupPresenter) {
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
        let button = OWSFlatButton()
        button.setBackgroundColors(upColor: Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_gray02)
        button.layer.cornerRadius = 8
        button.clipsToBounds = true

        // Icon

        let iconContainer = UIView()
        let iconView = UIImageView(image: UIImage(named: iconName))
        iconView.contentMode = .scaleAspectFit
        iconContainer.addSubview(iconView)
        iconView.autoPinWidthToSuperview()
        iconView.autoSetDimensions(to: CGSize(square: 48))
        iconView.autoVCenterInSuperview()
        iconView.autoMatch(.height, to: .height, of: iconContainer, withOffset: 0, relation: .lessThanOrEqual)

        // Labels

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.font = UIFont.dynamicTypeBody.semibold()
        titleLabel.textColor = Theme.primaryTextColor

        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.font = .dynamicTypeBody2
        bodyLabel.textColor = Theme.secondaryTextAndIconColor

        let topSpacer = UIView.vStretchingSpacer()
        let bottomSpacer = UIView.vStretchingSpacer()

        let vStack = UIStackView(arrangedSubviews: [
            topSpacer,
            titleLabel,
            bodyLabel,
            bottomSpacer
        ])
        vStack.axis = .vertical
        vStack.spacing = 8

        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)

        // Disclosure Indicator

        let disclosureContainer = UIView()
        let disclosureView = UIImageView()
        disclosureView.setTemplateImage(
            UIImage(imageLiteralResourceName: "chevron-right-20"),
            tintColor: Theme.secondaryTextAndIconColor
        )
        disclosureView.contentMode = .scaleAspectFit
        disclosureContainer.addSubview(disclosureView)
        disclosureView.autoPinEdgesToSuperviewEdges()
        disclosureView.autoSetDimension(.width, toSize: 20)

        let hStack = UIStackView(arrangedSubviews: [
            iconContainer,
            vStack,
            disclosureContainer
        ])
        hStack.axis = .horizontal
        hStack.spacing = 16
        hStack.isLayoutMarginsRelativeArrangement = true
        hStack.layoutMargins = UIEdgeInsets(top: 24, leading: 16, bottom: 24, trailing: 16)
        hStack.isUserInteractionEnabled = false

        button.addSubview(hStack)
        hStack.autoPinEdgesToSuperviewEdges()

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
#if USE_DEBUG_UI && TESTABLE_BUILD
        if Platform.isSimulator {
            DebugUIMisc.debugOnly_savePlaintextDbKey()
        }
#endif

        let actionSheet = ActionSheetController(title: "Choose backup import source:")
        let localFileAction = ActionSheetAction(title: "Local backup") { [weak self] _ in
            self?.showMessageBackupPicker()
        }
        actionSheet.addAction(localFileAction)
        let remoteFileAction = ActionSheetAction(title: "Remote backup") { [weak self] _ in
            self?.presenter?.didSelectBackup(type: .remote)
        }
        actionSheet.addAction(remoteFileAction)
        presentActionSheet(actionSheet)
    }

    @objc
    private func didSkipRestore() {
        presenter?.skipRestoreFromBackup()
    }

    private func showMessageBackupPicker() {
        let vc = UIApplication.shared.frontmostViewController!
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: !Platform.isSimulator)
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false
        vc.present(documentPicker, animated: true)
    }
}

extension RegistrationRestoreFromBackupViewController: UIDocumentPickerDelegate {

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let fileUrl = urls.first else {
            return
        }
        presenter?.didSelectBackup(type: .local(fileUrl: fileUrl))
    }
}
