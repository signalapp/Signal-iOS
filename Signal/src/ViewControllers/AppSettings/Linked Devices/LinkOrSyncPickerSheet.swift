//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class LinkOrSyncPickerSheet: StackSheetViewController {

    override var handleBackgroundColor: UIColor { .clear }

    override var sheetBackgroundColor: UIColor {
        UIColor.Signal.groupedBackground
    }

    private let hMargin: CGFloat = 20
    override var stackViewInsets: UIEdgeInsets {
        UIEdgeInsets(top: 0, leading: hMargin, bottom: 24, trailing: hMargin)
    }

    private let currentBackupPlan: BackupPlan
    private let freeTierMediaDays: UInt64
    private let didDismiss: () -> Void
    private let linkAndSync: () -> Void
    private let linkOnly: () -> Void

    private var didSelectAnAction = false

    init(
        currentBackupPlan: BackupPlan,
        freeTierMediaDays: UInt64,
        didDismiss: @escaping () -> Void,
        linkAndSync: @escaping () -> Void,
        linkOnly: @escaping () -> Void,
    ) {
        self.currentBackupPlan = currentBackupPlan
        self.freeTierMediaDays = freeTierMediaDays
        self.didDismiss = didDismiss
        self.linkAndSync = linkAndSync
        self.linkOnly = linkOnly
        super.init()
    }

    static func load(
        didDismiss: @escaping () -> Void,
        linkAndSync: @escaping () -> Void,
        linkOnly: @escaping () -> Void,
    ) -> LinkOrSyncPickerSheet {
        let backupSettingsStore = BackupSettingsStore()
        let db = DependenciesBridge.shared.db
        let subscriptionConfigManager = DependenciesBridge.shared.subscriptionConfigManager
        let (currentBackupPlan, freeTierMediaDays): (
            BackupPlan,
            UInt64,
        ) = db.read { tx in
            (
                backupSettingsStore.backupPlan(tx: tx),
                subscriptionConfigManager.backupConfigurationOrDefault(tx: tx).freeTierMediaDays,
            )
        }

        return LinkOrSyncPickerSheet(
            currentBackupPlan: currentBackupPlan,
            freeTierMediaDays: freeTierMediaDays,
            didDismiss: didDismiss,
            linkAndSync: linkAndSync,
            linkOnly: linkOnly,
        )
    }

    // MARK: -

    override func viewDidLoad() {
        super.viewDidLoad()

        self.stackView.alignment = .fill
        self.stackView.spacing = 16

        let titleContainer = UIView()
        let titleLabel = UILabel()
        titleContainer.addSubview(titleLabel)
        titleLabel.text = OWSLocalizedString(
            "LINK_DEVICE_CONFIRMATION_ALERT_TITLE",
            comment: "confirm the users intent to link a new device",
        )
        titleLabel.font = .dynamicTypeHeadlineClamped
        titleLabel.textColor = UIColor.Signal.label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        // Give space for the close button
        titleLabel.autoPinEdgesToSuperviewEdges(
            with: .init(hMargin: 36, vMargin: 0),
        )
        self.stackView.addArrangedSubview(titleContainer)
        self.stackView.setCustomSpacing(33, after: titleContainer)

        var closeButtonConfig = UIButton.Configuration.gray()
        closeButtonConfig.cornerStyle = .capsule
        closeButtonConfig.baseForegroundColor = UIColor.Signal.label
        closeButtonConfig.baseBackgroundColor = UIColor.Signal.tertiaryFill

        let closeButton = UIButton(
            configuration: closeButtonConfig,
            primaryAction: .init(
                image: UIImage(named: "x-compact-bold"),
            ) { [weak self] _ in
                self?.dismiss(animated: true)
            },
        )

        contentView.addSubview(closeButton)
        closeButton.autoPinEdge(toSuperviewEdge: .trailing, withInset: hMargin)
        closeButton.autoAlignAxis(.horizontal, toSameAxisOf: titleLabel)
        closeButton.autoSetDimensions(to: .square(28))

        self.stackView.addArrangedSubviews([
            self.actionRow(
                icon: "chat-check",
                titleText: OWSLocalizedString(
                    "LINK_DEVICE_CONFIRMATION_ALERT_TRANSFER_TITLE",
                    comment: "title for choosing to send message history when linking a new device",
                ),
                subtitleText: {
                    switch currentBackupPlan {
                    case .disabled, .disabling, .free:
                        String.localizedStringWithFormat(
                            OWSLocalizedString(
                                "LINK_DEVICE_CONFIRMATION_ALERT_TRANSFER_SUBTITLE_%d",
                                tableName: "PluralAware",
                                comment: "Subtitle for choosing to send message history when linking a new device. Embeds {{ the number of days that files are available, e.g. '45' }}.",
                            ),
                            freeTierMediaDays,
                        )
                    case .paid, .paidExpiringSoon, .paidAsTester:
                        OWSLocalizedString(
                            "LINK_DEVICE_CONFIRMATION_ALERT_TRANSFER_PAID_PLAN_SUBTITLE",
                            comment: "Subtitle for choosing to send message history when linking a new device, if you have the paid tier enabled.",
                        )
                    }
                }(),
            ) { [weak self] in
                guard let self else { return }
                self.didSelectAnAction = true
                let linkAndSync = self.linkAndSync
                self.dismiss(animated: true) {
                    linkAndSync()
                }
            },
            self.actionRow(
                icon: "chat-x",
                titleText: OWSLocalizedString(
                    "LINK_DEVICE_CONFIRMATION_ALERT_DONT_TRANSFER_TITLE",
                    comment: "title for declining to send message history when linking a new device",
                ),
                subtitleText: OWSLocalizedString(
                    "LINK_DEVICE_CONFIRMATION_ALERT_DONT_TRANSFER_SUBTITLE",
                    comment: "subtitle for declining to send message history when linking a new device",
                ),
            ) { [weak self] in
                guard let self else { return }
                self.didSelectAnAction = true
                let linkOnly = self.linkOnly
                self.dismiss(animated: true) {
                    linkOnly()
                }
            },
        ])
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if !didSelectAnAction {
            self.didDismiss()
        }
    }

    // MARK: Action row

    private func actionRow(
        icon: String,
        titleText: String,
        subtitleText: String,
        action: @escaping () -> Void,
    ) -> UIView {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 16
        stackView.alignment = .center
        stackView.layer.cornerRadius = 10
        stackView.backgroundColor = UIColor.Signal.secondaryGroupedBackground
        stackView.layoutMargins = .init(hMargin: 16, vMargin: 21)
        stackView.isLayoutMarginsRelativeArrangement = true

        let imageView = UIImageView()
        imageView.setTemplateImageName(
            icon,
            tintColor: .Signal.accent,
        )
        imageView.autoSetDimensions(to: .square(40))
        imageView.setContentHuggingHigh()
        imageView.setCompressionResistanceHigh()
        stackView.addArrangedSubview(imageView)

        let label = UILabel()
        label.numberOfLines = 0
        label.attributedText = .composed(of: [
            titleText.styled(
                with: .font(.dynamicTypeHeadline),
                .color(UIColor.Signal.label),
            ),
            "\n",
            subtitleText.styled(
                with: .font(.dynamicTypeFootnote),
                .color(UIColor.Signal.secondaryLabel),
            ),
        ])
        stackView.addArrangedSubview(label)

        let chevron = UIImageView()
        chevron.setTemplateImageName(
            "chevron-right-20",
            tintColor: UIColor.Signal.tertiaryLabel,
        )
        chevron.setContentHuggingHigh()
        chevron.setCompressionResistanceHigh()
        stackView.addArrangedSubview(chevron)

        let button = OWSButton(block: action)

        button.dimsWhenHighlighted = true
        stackView.isUserInteractionEnabled = false
        button.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()

        return button
    }
}

// MARK: - Previews

#if DEBUG
@available(iOS 17, *)
#Preview {
    SheetPreviewViewController(sheet: LinkOrSyncPickerSheet(
        currentBackupPlan: .paid(optimizeLocalStorage: false),
        freeTierMediaDays: 45,
        didDismiss: { print("didDismiss") },
        linkAndSync: { print("linkAndSync") },
        linkOnly: { print("linkOnly") },
    ))
}
#endif
