//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

class LocalFileBackupOnboardingIntroViewController: OWSViewController {
    private let onContinue: (UIViewController) -> Void

    init(onContinue: @escaping (UIViewController) -> Void) {
        self.onContinue = onContinue
        super.init()
        OWSTableViewController2.removeBackButtonText(viewController: self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .Signal.groupedBackground

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let contentStack = buildContentStack()
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        let continueButton = UIButton(
            configuration: .largePrimary(title: CommonStrings.continueButton),
            primaryAction: UIAction { [weak self] _ in self?.didTapContinue() },
        )

        let footerStack = UIStackView.verticalButtonStack(buttons: [continueButton])
        footerStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        view.addSubview(footerStack)

        NSLayoutConstraint.activate([
            footerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footerStack.topAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    // MARK: -

    private func buildContentStack() -> UIStackView {
        let logo = UIImageView(image: UIImage(named: "backups-on-device"))
        logo.contentMode = .scaleAspectFit
        logo.isAccessibilityElement = false
        logo.autoSetDimensions(to: .square(80))

        let titleLabel = UILabel()
        titleLabel.text = OWSLocalizedString(
            "LOCAL_FILE_BACKUP_ONBOARDING_INTRO_TITLE",
            comment: "Title for a view introducing local file backups during the onboarding flow.",
        )
        titleLabel.font = UIFont.dynamicTypeFont(ofStandardSize: 26).semibold()
        titleLabel.textColor = .Signal.label
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center

        let subtitleLabel = UILabel()
        subtitleLabel.text = OWSLocalizedString(
            "LOCAL_FILE_BACKUP_ONBOARDING_INTRO_SUBTITLE",
            comment: "Subtitle for a view introducing local file backups during the onboarding flow.",
        )
        subtitleLabel.font = .dynamicTypeBodyClamped
        subtitleLabel.textColor = .Signal.secondaryLabel
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textAlignment = .center

        let bulletsStack = UIStackView(arrangedSubviews: [
            buildBulletView(
                image: UIImage(resource: .lock),
                text: OWSLocalizedString(
                    "LOCAL_FILE_BACKUP_ONBOARDING_INTRO_BULLET_1",
                    comment: "Bullet point on a view introducing local file backups during onboarding flow.",
                ),
            ),
            buildBulletView(
                image: UIImage(resource: .checkSquare),
                text: OWSLocalizedString(
                    "LOCAL_FILE_BACKUP_ONBOARDING_INTRO_BULLET_2",
                    comment: "Bullet point on a view introducing local file backups during onboarding flow.",
                ),
            ),
            buildBulletView(
                image: UIImage(resource: .trash),
                text: OWSLocalizedString(
                    "LOCAL_FILE_BACKUP_ONBOARDING_INTRO_BULLET_3",
                    comment: "Bullet point on a view introducing local file backups during onboarding flow.",
                ),
            ),
        ])
        bulletsStack.axis = .vertical
        bulletsStack.spacing = 26

        let bulletsContainer = UIStackView(arrangedSubviews: [bulletsStack])
        bulletsContainer.isLayoutMarginsRelativeArrangement = true
        bulletsContainer.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24)

        let stack = UIStackView(arrangedSubviews: [
            logo,
            titleLabel,
            subtitleLabel,
            bulletsContainer,
        ])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 0
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 20, leading: 32, bottom: 0, trailing: 32)
        stack.setCustomSpacing(16, after: logo)
        stack.setCustomSpacing(12, after: titleLabel)
        stack.setCustomSpacing(36, after: subtitleLabel)

        return stack
    }

    private func buildBulletView(image: UIImage, text: String) -> UIView {
        let imageView = UIImageView(image: image.withRenderingMode(.alwaysTemplate))
        imageView.tintColor = .Signal.label
        imageView.autoSetDimensions(to: .square(24))

        let label = UILabel()
        label.text = text
        label.font = .dynamicTypeBodyClamped
        label.textColor = .Signal.label
        label.numberOfLines = 0

        let row = UIStackView(arrangedSubviews: [imageView, label])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center

        return row
    }

    private func didTapContinue() {
        onContinue(self)
    }
}
