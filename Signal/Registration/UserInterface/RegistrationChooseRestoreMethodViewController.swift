//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI

protocol RegistrationChooseRestoreMethodPresenter: AnyObject {
    func didChooseRestoreMethod(method: RegistrationRestoreMethod)
    func didCancelRestoreMethodSelection()
}

public enum RegistrationRestoreMethod {
    case deviceTransfer
    case local
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
            comment: "The title for the device transfer 'choice' view 'restore backup' option"
        ),
        body: OWSLocalizedString(
            "ONBOARDING_CHOOSE_RESTORE_METHOD_BACKUPS_BODY",
            comment: "The body for the device transfer 'choice' view 'restore backup' option"
        ),
        iconName: "signal-backups-48",
        iconSize: 48,
        selector: #selector(didSelectRestoreFromBackup)
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
        iconName: "transfer-48",
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
        iconName: "continue-48",
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

        let stackView = UIStackView()
        var anchorView: UIView?
        switch self.restorePath {
        case .quickRestore(let tier, let platform) where platform == .android:
            switch tier {
            case .free, .paid:
                addDefaultTitle(stackView)
                stackView.addArrangedSubviews([
                    restoreFromBackupButton,
                    prominentSkipRestoreButton
                ])
            case .none:
                addNoRestoreOptionViews(stackView)
            }
        case .quickRestore(let tier, _):
            addDefaultTitle(stackView)
            switch tier {
            case .free:
                stackView.addArrangedSubviews([
                    transferButton,
                    restoreFromBackupButton
                ])
                addSmallSkipRestoreButton()
                anchorView = smallSkipRestoreButton
            case .paid:
                stackView.addArrangedSubviews([
                    restoreFromBackupButton,
                    transferButton
                ])
                addSmallSkipRestoreButton()
                anchorView = smallSkipRestoreButton
            case .none:
                stackView.addArrangedSubviews([
                    transferButton,
                    prominentSkipRestoreButton
                ])
            }
        case .manualRestore:
            addDefaultTitle(stackView)
            stackView.addArrangedSubviews([
                restoreFromBackupButton,
                prominentSkipRestoreButton,
            ])
            view.addSubview(cancelButton)
            cancelButton.autoHCenterInSuperview()
            cancelButton.autoPinBottomToSuperviewMargin(withInset: 14)
            anchorView = cancelButton
        case .unspecified:
            addDefaultTitle(stackView)
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
        scrollView.addSubview(stackView)

        scrollView.autoPinEdges(toSuperviewEdgesExcludingEdge: .bottom)
        if let anchorView {
            scrollView.autoPinEdge(.bottom, to: .top, of: anchorView)
        } else {
            scrollView.autoPinEdge(toSuperviewEdge: .bottom)
        }

        stackView.autoPinWidth(toWidthOf: scrollView)
        stackView.autoPinEdge(toSuperviewEdge: .top)
        stackView.autoPinHeightToSuperviewMargins()

        render()
    }

    private func addDefaultTitle(_ stackView: UIStackView) {
        stackView.addArrangedSubviews([
            titleLabel,
            explanationLabel
        ])
        stackView.setCustomSpacing(12, after: titleLabel)
        stackView.setCustomSpacing(24, after: explanationLabel)
    }

    private func addSmallSkipRestoreButton() {
        view.addSubview(smallSkipRestoreButton)
        smallSkipRestoreButton.autoHCenterInSuperview()
        smallSkipRestoreButton.autoPinBottomToSuperviewMargin(withInset: 14)
    }

    private func addNoRestoreOptionViews(_ stackView: UIStackView) {
        let title = UILabel.titleLabelForRegistration(
            text: OWSLocalizedString(
                "ONBOARDING_CHOOSE_RESTORE_METHOD_NONE_AVAILABLE_TITLE",
                comment: "Title displayed to a user during registration if there are no restore options available."
            )
        )
        let body = UILabel.explanationLabelForRegistration(
            text: OWSLocalizedString(
                "ONBOARDING_CHOOSE_RESTORE_METHOD_NONE_AVAILABLE_BODY",
                comment: "Message body displayed to a user during registration if there are no restore options available."
            )
        )
        stackView.addArrangedSubviews([
            title,
            body
        ])
        stackView.setCustomSpacing(12, after: title)
        stackView.setCustomSpacing(32, after: body)

        func labelWithImage(imageName: String, text: String) -> UIView {
            let image = UIImageView(image: UIImage(named: imageName)?.withRenderingMode(.alwaysTemplate))
            image.tintColor = UIColor.colorForRegistrationExplanationLabel
            let label = UILabel.explanationLabelForRegistration(text: text)
            label.textAlignment = .natural
            let stackView = UIStackView(
                arrangedSubviews: [
                    image,
                    label,
                    SpacerView()
                ]
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
                comment: "First step in directions for how to make a backup"
            )),
            labelWithImage(imageName: "backup", text: OWSLocalizedString(
                "REGISTRATION_RESTORE_METHOD_MAKE_BACKUP_TUTORIAL_TAP_SETTINGS",
                comment: "Second step in directions for how to make a backup"
            )),
            labelWithImage(imageName: "check-circle", text: OWSLocalizedString(
                "REGISTRATION_RESTORE_METHOD_MAKE_BACKUP_TUTORIAL_ENABLE_BACKUPS",
                comment: "Third step in directions for how to make a backup"
            ))
        ])

        // Show the 'No backup to restore'
        let continueButton = OWSFlatButton.primaryButtonForRegistration(
            title: CommonStrings.okayButton,
            target: self,
            selector: #selector(didTapCancel)
        )
        view.addSubview(continueButton)
        continueButton.autoSetDimension(.width, toSize: 280)
        continueButton.autoHCenterInSuperview()

        addSmallSkipRestoreButton()

        continueButton.autoPinEdge(.bottom, to: .top, of: smallSkipRestoreButton, withOffset: -24)
    }

    private func render() {
        view.backgroundColor = Theme.backgroundColor
        titleLabel.textColor = .colorForRegistrationTitleLabel
        explanationLabel.textColor = .colorForRegistrationExplanationLabel
    }

    // MARK: Events

    @objc
    private func didSelectRestoreFromBackup() {
        presenter?.didChooseRestoreMethod(method: .remote)
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

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        render()
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
        )
    )
}

@available(iOS 17, *)
#Preview("Quick Restore iOS paid") {
    OWSNavigationController(
        rootViewController: RegistrationChooseRestoreMethodViewController(
            presenter: presenter,
            restorePath: .quickRestore(.paid, .ios),
        )
    )
}

@available(iOS 17, *)
#Preview("Quick Restore iOS no backups") {
    OWSNavigationController(
        rootViewController: RegistrationChooseRestoreMethodViewController(
            presenter: presenter,
            restorePath: .quickRestore(nil, .ios),
        )
    )
}

@available(iOS 17, *)
#Preview("Quick Restore Android source, free") {
    OWSNavigationController(
        rootViewController: RegistrationChooseRestoreMethodViewController(
            presenter: presenter,
            restorePath: .quickRestore(.free, .android),
        )
    )
}

@available(iOS 17, *)
#Preview("Quick Restore Android source, paid") {
    OWSNavigationController(
        rootViewController: RegistrationChooseRestoreMethodViewController(
            presenter: presenter,
            restorePath: .quickRestore(.paid, .android),
        )
    )
}

@available(iOS 17, *)
#Preview("Quick Restore Android source, no backup") {
    OWSNavigationController(
        rootViewController: RegistrationChooseRestoreMethodViewController(
            presenter: presenter,
            restorePath: .quickRestore(nil, .android),
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
