//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import SignalServiceKit

class LinkedDevicesEducationSheet: StackSheetViewController {

    override var stackViewInsets: UIEdgeInsets {
        .init(top: 8, leading: 40, bottom: 24, trailing: 40)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        stackView.spacing = 32

        let imageView = UIImageView(image: UIImage(named: "all-devices"))
        imageView.contentMode = .center
        stackView.addArrangedSubview(imageView)
        stackView.setCustomSpacing(20, after: imageView)

        let titleLabel = UILabel()
        titleLabel.font = .dynamicTypeTitle2
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center
        titleLabel.text = OWSLocalizedString(
            "LINKED_DEVICES_EDUCATION_TITLE",
            comment: "Title for the linked device education sheet"
        )
        stackView.addArrangedSubview(titleLabel)
        stackView.setCustomSpacing(24, after: titleLabel)

        let privacyBulletPoint = Self.bulletPoint(
            icon: "lock",
            text: OWSLocalizedString(
                "LINKED_DEVICES_EDUCATION_POINT_PRIVACY",
                comment: "Bullet point about privacy on the linked devices education sheet"
            )
        )
        stackView.addArrangedSubview(privacyBulletPoint)

        let messagesBulletPoint = Self.bulletPoint(
            icon: "thread",
            text: OWSLocalizedString(
                "LINKED_DEVICES_EDUCATION_POINT_MESSAGES",
                comment: "Bullet point about message sync on the linked devices education sheet"
            )
        )
        stackView.addArrangedSubview(messagesBulletPoint)

        let iPadDownloadLinkString = "signal.org/install"
        let iPadDownloadURL = URL(string: "https://signal.org/install/")!
        let desktopDownloadLinkString = "signal.org/download"
        let desktopDownloadURL = URL(string: "https://signal.org/download/")!

        let downloadsString = String(
            format: OWSLocalizedString(
                "LINKED_DEVICES_EDUCATION_POINT_DOWNLOADS",
                comment: "Bullet point about downloads on the linked devices education sheet. Embeds {{ %1$@ iPad download link, %2$@ desktop download link }}"
            ),
            iPadDownloadLinkString, desktopDownloadLinkString
        )

        let downloadsAttributedString = NSMutableAttributedString(string: downloadsString)

        downloadsAttributedString.addAttributes(
            [.link: iPadDownloadURL],
            range: (downloadsString as NSString).range(of: iPadDownloadLinkString)
        )

        downloadsAttributedString.addAttributes(
            [.link: desktopDownloadURL],
            range: (downloadsString as NSString).range(of: desktopDownloadLinkString)
        )

        let downloadsBulletPoint = Self.bulletPoint(
            icon: "save",
            text: downloadsAttributedString
        )

        stackView.addArrangedSubview(downloadsBulletPoint)
    }

    private static func bulletPoint(icon: String, text: String) -> UIView {
        bulletPoint(icon: icon, text: NSAttributedString(string: text))
    }

    private static func bulletPoint(
        icon: String,
        text: NSAttributedString
    ) -> UIView {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 24
        stackView.alignment = .top

        let iconView = UIImageView(image: UIImage(named: icon))
        iconView.tintColor = .Signal.label
        iconView.setCompressionResistanceHigh()
        stackView.addArrangedSubview(iconView)

        let textView = LinkingTextView()
        textView.setContentHuggingLow()
        textView.attributedText = text.styled(
            with: .font(.dynamicTypeBody2),
            .color(UIColor.Signal.label)
        )
        stackView.addArrangedSubview(textView)

        return stackView
    }
}
