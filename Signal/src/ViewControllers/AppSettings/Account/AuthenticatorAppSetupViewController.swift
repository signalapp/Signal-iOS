//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// Walks the user through the steps required to add their Signal account to
/// an authenticator app, either by opening the app directly or by copying a setup key.
class AuthenticatorAppSetupViewController: OWSTableViewController2 {

    /// Width of the illustration column on the trailing side of each step.
    private static let imageColumnWidth: CGFloat = 64.0

    private let setupKey: String
    private let provisioningURL: URL
    private let onContinue: () -> Void

    init(
        setupKey: String,
        provisioningURL: URL,
        onContinue: @escaping () -> Void,
    ) {
        self.setupKey = setupKey
        self.provisioningURL = provisioningURL
        self.onContinue = onContinue
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "AUTHENTICATOR_APP_SETUP_TITLE",
            comment: "Title for the screen that explains how to setup an authenticator app.",
        )

        let installSection = OWSTableSection()
        // TODO[#less]: Link to an authenticator app support article once there is one.
        installSection.headerAttributedTitle = NSAttributedString.composed(of: [
            OWSLocalizedString(
                "AUTHENTICATOR_APP_SETUP_DESCRIPTION",
                comment: "Body for the screen that explains how to setup an authenticator app.",
            ),
            "\n",
            CommonStrings.learnMore.styled(with: .link(URL.Support.generic)),
        ])
        .styled(with: Self.defaultFooterTextStyle)
        installSection.add(OWSTableItem(customCellBlock: { [weak self] in
            self?.installStepCell() ?? UITableViewCell()
        }))

        let addAccountSection = OWSTableSection()
        addAccountSection.add(OWSTableItem(customCellBlock: { [weak self] in
            self?.addAccountStepCell() ?? UITableViewCell()
        }))

        let enterCodeSection = OWSTableSection()
        enterCodeSection.add(OWSTableItem(customCellBlock: { [weak self] in
            self?.enterCodeStepCell() ?? UITableViewCell()
        }))

        contents = OWSTableContents(sections: [installSection, addAccountSection, enterCodeSection])
    }

    // MARK: Step cells

    private func installStepCell() -> UITableViewCell {
        let linkText = OWSLocalizedString(
            "AUTHENTICATOR_APP_SETUP_STEP_1_LINK",
            comment: "Linked text in step 1 of authenticator setup, embedded in AUTHENTICATOR_APP_SETUP_STEP_1_BODY_FORMAT.",
        )
        let bodyFormat = OWSLocalizedString(
            "AUTHENTICATOR_APP_SETUP_STEP_1_BODY_FORMAT",
            comment: "Instructions for step 1 of authenticator setup. Embeds {{AUTHENTICATOR_APP_SETUP_STEP_1_LINK}}, which links to a list of authenticator apps.",
        )
        let body = NSMutableAttributedString(
            string: String.nonPluralLocalizedStringWithFormat(bodyFormat, linkText),
            attributes: [.font: UIFont.dynamicTypeSubheadline, .foregroundColor: UIColor.Signal.secondaryLabel],
        )
        let linkRange = (body.string as NSString).range(of: linkText)
        if linkRange.location != NSNotFound {
            // TODO[#less]: Link to a list of trusted authenticator apps
            body.addAttributes(
                [
                    .link: URL.Support.generic,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ],
                range: linkRange,
            )
        }
        let bodyView = LinkingTextView()
        bodyView.attributedText = body
        bodyView.linkTextAttributes = [.foregroundColor: UIColor.Signal.label]

        return stepCell(
            title: stepTitle(1),
            bodyView: bodyView,
            image: .twoFactorDownload,
            imageWidth: 48.0,
        )
    }

    private func addAccountStepCell() -> UITableViewCell {
        let openButton = smallButton(
            title: OWSLocalizedString(
                "AUTHENTICATOR_APP_SETUP_OPEN_BUTTON",
                comment: "Button in step 2 of setup that opens authenticator app",
            ),
            image: .arrowSquareUprightLight,
        ) { [weak self] in
            self?.didTapOpen()
        }

        let divider = UIView()
        divider.backgroundColor = .Signal.opaqueSeparator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true

        let copyExplanationLabel = bodyLabel(OWSLocalizedString(
            "AUTHENTICATOR_APP_SETUP_COPY_KEY_DESCRIPTION",
            comment: "Description for step 2 of authenticator app setup",
        ))
        copyExplanationLabel.textColor = .Signal.label

        let keyLabel = UILabel()
        keyLabel.text = setupKey
        keyLabel.font = UIFont.monospacedSystemFont(
            ofSize: UIFont.dynamicTypeSubheadline.pointSize,
            weight: .regular,
        )
        keyLabel.textColor = .Signal.label
        keyLabel.numberOfLines = 0
        keyLabel.lineBreakMode = .byCharWrapping

        let copyButton = smallButton(
            title: CommonStrings.copyButton,
            image: .copyLight,
        ) { [weak self] in
            self?.didTapCopy()
        }

        let cell = stepCell(
            title: stepTitle(2),
            bodyView: bodyLabel(OWSLocalizedString(
                "AUTHENTICATOR_APP_SETUP_STEP_2_BODY",
                comment: "Instructions for step 2 of authenticator app setup.",
            )),
            image: .twoFactorAuthenticator,
            imageWidth: 64.0,
            additionalViews: [
                openButton.wrappedInContainerView(alignment: .leading),
                divider,
                copyExplanationLabel,
                keyLabel,
                copyButton.wrappedInContainerView(alignment: .leading),
            ],
        )
        return cell
    }

    private func enterCodeStepCell() -> UITableViewCell {
        return stepCell(
            title: stepTitle(3),
            bodyView: bodyLabel(OWSLocalizedString(
                "AUTHENTICATOR_APP_SETUP_STEP_3_BODY",
                comment: "Instructions for step 3 of authenticator app setup.",
            )),
            image: .twoFactorCode,
            imageWidth: 56.0,
        )
    }

    private func stepTitle(_ number: Int) -> String {
        String.nonPluralLocalizedStringWithFormat(
            OWSLocalizedString(
                "AUTHENTICATOR_APP_SETUP_STEP_TITLE_FORMAT",
                comment: "Title for each step of authenticator app setup. Embeds {{step number}}.",
            ),
            OWSFormat.formatInt(number),
        )
    }

    private func bodyLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .dynamicTypeSubheadline
        label.textColor = .Signal.secondaryLabel
        label.numberOfLines = 0
        return label
    }

    private func smallButton(
        title: String,
        image: UIImage,
        action: @escaping () -> Void,
    ) -> UIButton {
        var configuration = UIButton.Configuration.smallSecondary(title: title)
        configuration.image = image.resized(maxDimensionPoints: 16)?.withRenderingMode(.alwaysTemplate)
        configuration.imagePadding = 4
        configuration.cornerStyle = .capsule
        return UIButton(
            configuration: configuration,
            primaryAction: UIAction { _ in action() },
        )
    }

    /// A card with a bold step title and instructions, an image on the
    /// trailing side, with an optional set of views to display along the bottom
    private func stepCell(
        title: String,
        bodyView: UIView,
        image: UIImage,
        imageWidth: CGFloat,
        additionalViews: [UIView] = [],
    ) -> UITableViewCell {
        let cell = OWSTableItem.newCell()
        cell.selectionStyle = .none

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .dynamicTypeHeadline
        titleLabel.textColor = .Signal.label
        titleLabel.numberOfLines = 0

        let textStack = UIStackView(arrangedSubviews: [titleLabel, bodyView])
        textStack.axis = .vertical
        textStack.spacing = 2

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false

        // Center each image in a fixed-width column so that every step image can
        // share a center line. Currently, this is set to a static `Self.imageColumnWidth`,
        // so if images wider than this are needed, that value should be increased.
        let imageColumn = UIView.transparentContainer()
        imageColumn.translatesAutoresizingMaskIntoConstraints = false
        imageColumn.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageColumn.widthAnchor.constraint(equalToConstant: Self.imageColumnWidth),
            imageView.widthAnchor.constraint(equalToConstant: imageWidth),
            imageView.heightAnchor.constraint(
                equalTo: imageView.widthAnchor,
                multiplier: image.size.height / image.size.width,
            ),
            imageView.centerXAnchor.constraint(equalTo: imageColumn.centerXAnchor),
            imageView.topAnchor.constraint(equalTo: imageColumn.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: imageColumn.bottomAnchor),
        ])

        let topRow = UIStackView(arrangedSubviews: [textStack, imageColumn])
        topRow.axis = .horizontal
        topRow.distribution = .fill
        topRow.alignment = .top
        topRow.spacing = 16

        let outerStack = UIStackView(arrangedSubviews: [topRow] + additionalViews)
        outerStack.axis = .vertical
        outerStack.spacing = 12
        if !additionalViews.isEmpty {
            outerStack.setCustomSpacing(8, after: topRow)
        }

        cell.contentView.addSubview(outerStack)
        outerStack.autoPinEdgesToSuperviewMargins()
        return cell
    }

    // MARK: Bottom footer

    private lazy var continueButton = UIButton(
        configuration: .largePrimary(title: CommonStrings.continueButton),
        primaryAction: UIAction { [weak self] _ in
            self?.onContinue()
        },
    )

    private lazy var bottomFooterContainer: UIView = {
        let stackView = UIStackView.verticalButtonStack(buttons: [continueButton])
        let view = UIView()
        view.preservesSuperviewLayoutMargins = true
        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        return view
    }()

    override func bottomFooter() -> UIView? { bottomFooterContainer }

    // MARK: Events

    private func didTapOpen() {
        UIApplication.shared.open(provisioningURL) { [weak self] didOpen in
            guard !didOpen, let self else { return }
            OWSActionSheets.showActionSheet(
                message: OWSLocalizedString(
                    "AUTHENTICATOR_APP_SETUP_OPEN_FAILED",
                    comment: "Shown when the user taps to open the authenticator, but no installed app can handle it.",
                ),
                fromViewController: self,
            )
        }
    }

    private func didTapCopy() {
        UIPasteboard.general.string = setupKey
        presentToast(text: CommonStrings.copiedToClipboardToast)
    }
}

#if DEBUG

@available(iOS 17, *)
#Preview {
    return OWSNavigationController(rootViewController: AuthenticatorAppSetupViewController(
        setupKey: "Test",
        provisioningURL: URL(string: "https://example.com")!,
        onContinue: {},
    ))
}

#endif
