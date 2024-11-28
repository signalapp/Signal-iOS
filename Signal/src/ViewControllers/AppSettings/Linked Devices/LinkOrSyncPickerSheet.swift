//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import SignalServiceKit

class LinkOrSyncPickerSheet: StackSheetViewController {

    override var handleBackgroundColor: UIColor { .clear }

    override var sheetBackgroundColor: UIColor {
        UIColor.Signal.groupedBackground
    }

    override var stackViewInsets: UIEdgeInsets {
        UIEdgeInsets(top: 0, leading: 20, bottom: 24, trailing: 20)
    }

    private let didDismiss: () -> Void
    private let linkAndSync: () -> Void
    private let linkOnly: () -> Void

    private var didSelectAnAction = false

    init(
        didDismiss: @escaping () -> Void,
        linkAndSync: @escaping () -> Void,
        linkOnly: @escaping () -> Void
    ) {
        self.didDismiss = didDismiss
        self.linkAndSync = linkAndSync
        self.linkOnly = linkOnly
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.stackView.alignment = .fill
        self.stackView.spacing = 16

        let titleContainer = UIView()
        let titleLabel = UILabel()
        titleContainer.addSubview(titleLabel)
        titleLabel.text = OWSLocalizedString(
            "LINK_DEVICE_CONFIRMATION_ALERT_TITLE",
            comment: "confirm the users intent to link a new device"
        )
        titleLabel.font = .dynamicTypeHeadlineClamped
        titleLabel.textColor = UIColor.Signal.label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        // Give space for the close button
        titleLabel.autoPinEdgesToSuperviewEdges(
            with: .init(hMargin: 36, vMargin: 0)
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
                image: UIImage(named: "x-compact-bold")
            ) { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )

        view.addSubview(closeButton)
        closeButton.autoPinEdge(toSuperviewMargin: .trailing)
        closeButton.autoAlignAxis(.horizontal, toSameAxisOf: titleLabel)
        closeButton.autoSetDimensions(to: .square(28))

        self.stackView.addArrangedSubviews([
            self.actionRow(
                icon: "chat-check",
                titleText: OWSLocalizedString(
                    "LINK_DEVICE_CONFIRMATION_ALERT_TRANSFER_TITLE",
                    comment: "title for choosing to send message history when linking a new device"
                ),
                subtitleText: OWSLocalizedString(
                    "LINK_DEVICE_CONFIRMATION_ALERT_TRANSFER_SUBTITLE",
                    comment: "subtitle for choosing to send message history when linking a new device"
                )
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
                    comment: "title for declining to send message history when linking a new device"
                ),
                subtitleText: OWSLocalizedString(
                    "LINK_DEVICE_CONFIRMATION_ALERT_DONT_TRANSFER_SUBTITLE",
                    comment: "subtitle for declining to send message history when linking a new device"
                )
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
        action: @escaping () -> Void
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
            tintColor: .Signal.accent
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
                .color(UIColor.Signal.label)
            ),
            "\n",
            subtitleText.styled(
                with: .font(.dynamicTypeFootnote),
                .color(UIColor.Signal.secondaryLabel)
            ),
        ])
        stackView.addArrangedSubview(label)

        let chevron = UIImageView()
        chevron.setTemplateImageName(
            "chevron-right-20",
            tintColor: UIColor.Signal.tertiaryLabel
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
    SheetPreviewViewController(sheet: LinkOrSyncPickerSheet {
        print("didDismiss")
    } linkAndSync: {
        print("linkAndSync")
    } linkOnly: {
        print("linkOnly")
    })
}
#endif
