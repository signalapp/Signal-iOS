//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class PasskeyEducationViewController: OWSViewController {

    private enum Constants {
        static let bodyHorizontalInset: CGFloat = 24
        static let bulletsHorizontalInset: CGFloat = 36
        static let buttonHorizontalInset: CGFloat = 24
        static let bulletSpacing: CGFloat = 24
        static let bulletIconSpacing: CGFloat = 12
    }

    private let onSetUpPasskey: () -> Void

    private lazy var imageView: UIImageView = {
        let imageView = UIImageView(image: .twoFactorPasskey)
        imageView.contentMode = .center
        imageView.isAccessibilityElement = false
        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.text = OWSLocalizedString(
            "PASSKEY_EDUCATION_TITLE",
            comment: "Title for a view introducing passkeys.",
        )
        titleLabel.font = .dynamicTypeTitle2Clamped.semibold()
        titleLabel.textColor = .Signal.label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.accessibilityTraits = .header
        return titleLabel
    }()

    init(onSetUpPasskey: @escaping () -> Void) {
        self.onSetUpPasskey = onSetUpPasskey
        super.init()

        navigationItem.rightBarButtonItem = .closeButton { [weak self] in
            self?.dismiss(animated: true)
        }
        OWSTableViewController2.removeBackButtonText(viewController: self)
    }

    // MARK: UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.groupedBackground

        let stackView = addStaticContentStackView(arrangedSubviews: [], isScrollable: true)
        stackView.spacing = 0

        stackView.addArrangedSubview(imageView)
        stackView.setCustomSpacing(16, after: imageView)

        stackView.addArrangedSubview(titleLabel)
        stackView.setCustomSpacing(12, after: titleLabel)

        // Body, with an inline "Learn more" link
        let bodyContainer = insetContainer(
            for: buildBodyTextView(),
            horizontalInset: Constants.bodyHorizontalInset,
        )
        stackView.addArrangedSubview(bodyContainer)
        stackView.setCustomSpacing(40, after: bodyContainer)

        let bulletsStack = UIStackView(arrangedSubviews: [
            buildBulletRow(
                image: .checkCircle,
                text: OWSLocalizedString(
                    "PASSKEY_EDUCATION_BULLET_NAME",
                    comment: "Bullet point explaining that a passkey can be given a name.",
                ),
            ),
            buildBulletRow(
                image: .lock,
                text: OWSLocalizedString(
                    "PASSKEY_EDUCATION_BULLET_STORAGE",
                    comment: "Bullet point explaining where a passkey is stored.",
                ),
            ),
            buildBulletRow(
                image: .trash,
                text: OWSLocalizedString(
                    "PASSKEY_EDUCATION_BULLET_MANAGE",
                    comment: "Bullet point explaining that passkeys can be added or removed.",
                ),
            ),
        ])
        bulletsStack.axis = .vertical
        bulletsStack.spacing = Constants.bulletSpacing
        stackView.addArrangedSubview(
            insetContainer(
                for: bulletsStack,
                horizontalInset: Constants.bulletsHorizontalInset,
            ),
        )

        let spacer = UIView.transparentSpacer()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        stackView.addArrangedSubview(spacer)
        stackView.setCustomSpacing(24, after: spacer)

        let setUpButton = UIButton(
            configuration: .largePrimary(title: OWSLocalizedString(
                "PASSKEY_EDUCATION_SET_UP_BUTTON",
                comment: "Button on a view introducing passkeys that starts setting up a passkey.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.onSetUpPasskey()
            },
        )
        stackView.addArrangedSubview(
            insetContainer(
                for: setUpButton,
                horizontalInset: Constants.buttonHorizontalInset,
            ),
        )
    }

    // MARK: Views

    private func buildBodyTextView() -> LinkingTextView {
        let textView = LinkingTextView()
        textView.linkTextAttributes = [.foregroundColor: UIColor.Signal.label]
        textView.adjustsFontForContentSizeCategory = true

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let text = NSMutableAttributedString(
            string: OWSLocalizedString(
                "PASSKEY_EDUCATION_BODY",
                comment: "Description introducing passkeys. Followed by a 'Learn more' link.",
            ),
            attributes: [
                .font: UIFont.dynamicTypeSubheadlineClamped,
                .foregroundColor: UIColor.Signal.secondaryLabel,
                .paragraphStyle: paragraphStyle,
            ],
        )
        text.append(NSAttributedString(
            string: " ",
            attributes: [.font: UIFont.dynamicTypeSubheadlineClamped],
        ))
        text.append(NSAttributedString(
            string: OWSLocalizedString(
                "PASSKEY_EDUCATION_LEARN_MORE",
                comment: "Link at the end of the view introducing passkeys.",
            ),
            attributes: [
                .font: UIFont.dynamicTypeSubheadlineClamped,
                // TODO[#less]: Link to a two-factor authentication support article once there is one.
                .link: URL.Support.generic,
                .paragraphStyle: paragraphStyle,
            ],
        ))
        textView.attributedText = text
        return textView
    }

    private func buildBulletRow(image: UIImage, text: String) -> UIView {
        let iconView = UIImageView(image: image)
        iconView.tintColor = .Signal.secondaryLabel
        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        let label = UILabel()
        label.text = text
        label.font = .dynamicTypeSubheadlineClamped
        label.textColor = .Signal.secondaryLabel
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true

        let row = UIStackView(arrangedSubviews: [iconView, label])
        row.axis = .horizontal
        row.alignment = .firstBaseline
        row.spacing = Constants.bulletIconSpacing
        return row
    }

    private func insetContainer(for subview: UIView, horizontalInset: CGFloat) -> UIView {
        let container = UIView.transparentContainer()
        container.addSubview(subview)
        subview.autoPinEdgesToSuperviewEdges(with: .init(hMargin: horizontalInset, vMargin: 0))
        return container
    }
}

// MARK: -

#if DEBUG

@available(iOS 17, *)
#Preview {
    SheetPreviewViewController(sheet: OWSNavigationController(rootViewController: PasskeyEducationViewController(
        onSetUpPasskey: { print("Set up passkey") },
    )))
}

#endif
