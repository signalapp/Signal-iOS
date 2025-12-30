//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI
import UIKit

class BadgeDetailsSheet: OWSTableSheetViewController {
    enum Owner: Equatable {
        // TODO: Eventually we won't need a short name for self, the server will provide copy for us.
        case local(shortName: String)
        case remote(shortName: String)

        func formattedDescription(for badge: ProfileBadge) -> String {
            switch self {
            case .local(let shortName):
                return badge.localizedDescriptionFormatString.replacingOccurrences(of: "{short_name}", with: shortName)
            case .remote(let shortName):
                return badge.localizedDescriptionFormatString.replacingOccurrences(of: "{short_name}", with: shortName)
            }
        }

        var isLocal: Bool {
            switch self {
            case .local: return true
            case .remote: return false
            }
        }
    }

    private let owner: Owner
    private let focusedBadge: ProfileBadge

    // TODO: support initializing with a list of available badges and paging between them
    init(focusedBadge: ProfileBadge, owner: Owner) {
        self.focusedBadge = focusedBadge
        self.owner = owner
        super.init()
    }

    // MARK: -

    private var remoteSupporterName: String? {
        guard focusedBadge.category == .donor else {
            return nil
        }

        let isGiftBadge = GiftBadgeIds.contains(focusedBadge.id)
        guard !isGiftBadge else {
            return nil
        }

        switch owner {
        case .local: return nil
        case let .remote(name): return name
        }
    }

    private func localProfileHasBadges() -> Bool {
        return SSKEnvironment.shared.databaseStorageRef.read { tx in SSKEnvironment.shared.profileManagerRef.localUserProfile(tx: tx)?.hasBadge == true }
    }

    private func shouldShowDonateButton() -> Bool {
        !owner.isLocal && !localProfileHasBadges()
    }

    override func tableContents() -> OWSTableContents {
        let contents = OWSTableContents()

        let focusedBadgeSection = OWSTableSection()
        focusedBadgeSection.hasBackground = false
        contents.add(focusedBadgeSection)

        focusedBadgeSection.add(.init(customCellBlock: { [weak self] in
            let cell = OWSTableItem.newCell()
            guard let self else { return cell }
            cell.selectionStyle = .none

            let badgeImageView = UIImageView()
            badgeImageView.image = self.focusedBadge.assets?.universal160
            let badgeImageContainer = UIView.container()
            badgeImageContainer.addSubview(badgeImageView)
            badgeImageView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                badgeImageView.widthAnchor.constraint(equalToConstant: 160),
                badgeImageView.heightAnchor.constraint(equalToConstant: 160),

                badgeImageView.leadingAnchor.constraint(greaterThanOrEqualTo: badgeImageContainer.leadingAnchor),
                badgeImageView.centerXAnchor.constraint(equalTo: badgeImageContainer.centerXAnchor),
                badgeImageView.topAnchor.constraint(equalTo: badgeImageContainer.topAnchor),
                badgeImageView.bottomAnchor.constraint(equalTo: badgeImageContainer.bottomAnchor, constant: -16),
            ])

            let text = {
                if let remoteSupporterName = self.remoteSupporterName {
                    let format = OWSLocalizedString(
                        "BADGE_DETAILS_TITLE_FOR_SUPPORTER",
                        comment: "When viewing someone else's donor badge, you'll see a sheet. This is the title on that sheet. Embeds {badge owner's short name}",
                    )
                    return String(format: format, remoteSupporterName)
                } else {
                    return self.focusedBadge.localizedName
                }
            }()
            let badgeLabel = UILabel.title2Label(text: text)

            let badgeDescription = UILabel.explanationTextLabel(text: self.owner.formattedDescription(for: self.focusedBadge))
            badgeDescription.setCompressionResistanceVerticalHigh()
            badgeDescription.setContentHuggingVerticalHigh()

            let stackView = UIStackView(arrangedSubviews: [
                badgeImageContainer,
                badgeLabel,
                badgeDescription,
            ])
            stackView.setCustomSpacing(36, after: badgeLabel)
            stackView.axis = .vertical
            stackView.alignment = .fill
            cell.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewEdges()

            return cell
        }, actionBlock: nil))

        if shouldShowDonateButton() {
            let buttonSection = OWSTableSection(items: [.init(customCellBlock: { [weak self] in
                let cell = OWSTableItem.newCell()
                cell.selectionStyle = .none

                guard let self else { return cell }
                let button = UIButton(
                    configuration: .largePrimary(title: OWSLocalizedString(
                        "BADGE_DETAILS_DONATE_TO_SIGNAL",
                        comment: "When viewing someone else's badge, you'll see a sheet. If they got the badge by donating, a \"Donate to Signal\" button will be shown. This is the text in that button.",
                    )),
                    primaryAction: UIAction { [weak self] _ in
                        self?.didTapDonate()
                    },
                )
                let buttonContainer = button.enclosedInVerticalStackView(isFullWidthButton: true)
                buttonContainer.directionalLayoutMargins.top = 16
                cell.contentView.addSubview(buttonContainer)
                buttonContainer.autoPinEdgesToSuperviewEdges()

                return cell
            })])
            buttonSection.hasBackground = false
            contents.add(buttonSection)
        }

        return contents
    }

    private func didTapDonate() {
        dismiss(animated: true) {
            if
                DonationUtilities.canDonateInAnyWay(
                    tsAccountManager: DependenciesBridge.shared.tsAccountManager,
                )
            {
                let frontVc = { CurrentAppContext().frontmostViewController() }

                let donateVc = DonateViewController(preferredDonateMode: .oneTime) { finishResult in
                    switch finishResult {
                    case let .completedDonation(donateSheet, receiptCredentialSuccessMode):
                        donateSheet.dismiss(animated: true) {
                            guard
                                let frontVc = frontVc(),
                                let badgeThanksSheetPresenter = BadgeThanksSheetPresenter.fromGlobalsWithSneakyTransaction(
                                    successMode: receiptCredentialSuccessMode,
                                )
                            else { return }

                            Task {
                                await badgeThanksSheetPresenter.presentAndRecordBadgeThanks(
                                    fromViewController: frontVc,
                                )
                            }
                        }
                    case let .monthlySubscriptionCancelled(donateSheet, toastText):
                        donateSheet.dismiss(animated: true) {
                            frontVc()?.presentToast(text: toastText)
                        }
                    }
                }
                let navigationVc = OWSNavigationController(rootViewController: donateVc)
                frontVc()?.present(navigationVc, animated: true)
            } else {
                DonationViewsUtil.openDonateWebsite()
            }
        }
    }
}
