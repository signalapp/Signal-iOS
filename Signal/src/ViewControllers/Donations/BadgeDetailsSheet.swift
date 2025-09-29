//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI
import UIKit

final class BadgeDetailsSheet: OWSTableSheetViewController {
    public enum Owner: Equatable {
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

    override public func updateTableContents(shouldReload: Bool = true) {
        let contents = OWSTableContents()
        defer { tableViewController.setContents(contents, shouldReload: shouldReload) }

        let focusedBadgeSection = OWSTableSection()
        focusedBadgeSection.hasBackground = false
        contents.add(focusedBadgeSection)

        focusedBadgeSection.add(.init(customCellBlock: { [weak self] in
            let cell = OWSTableItem.newCell()
            guard let self = self else { return cell }
            cell.selectionStyle = .none

            let stackView = UIStackView()
            stackView.axis = .vertical
            stackView.alignment = .center

            cell.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewMargins()

            let badgeImageView = UIImageView()
            badgeImageView.image = self.focusedBadge.assets?.universal160
            badgeImageView.autoSetDimensions(to: CGSize(square: 160))
            stackView.addArrangedSubview(badgeImageView)
            stackView.setCustomSpacing(14, after: badgeImageView)

            let badgeLabel = UILabel()
            badgeLabel.font = .dynamicTypeTitle3.semibold()
            badgeLabel.textColor = Theme.primaryTextColor
            badgeLabel.textAlignment = .center
            badgeLabel.numberOfLines = 0
            badgeLabel.text = {
                if let remoteSupporterName = self.remoteSupporterName {
                    let format = OWSLocalizedString(
                        "BADGE_DETAILS_TITLE_FOR_SUPPORTER",
                        comment: "When viewing someone else's donor badge, you'll see a sheet. This is the title on that sheet. Embeds {badge owner's short name}"
                    )
                    return String(format: format, remoteSupporterName)
                } else {
                    return self.focusedBadge.localizedName
                }
            }()
            stackView.addArrangedSubview(badgeLabel)
            stackView.setCustomSpacing(36, after: badgeLabel)

            let badgeDescription = UILabel()
            badgeDescription.font = .dynamicTypeBody
            badgeDescription.textColor = Theme.primaryTextColor
            badgeDescription.textAlignment = .center
            badgeDescription.numberOfLines = 0
            badgeDescription.text = self.owner.formattedDescription(for: self.focusedBadge)
            badgeDescription.setCompressionResistanceVerticalHigh()
            badgeDescription.setContentHuggingVerticalHigh()
            stackView.addArrangedSubview(badgeDescription)
            stackView.setCustomSpacing(30, after: badgeDescription)

            return cell
        }, actionBlock: nil))

        if shouldShowDonateButton() {
            let buttonSection = OWSTableSection(items: [.init(customCellBlock: { [weak self] in
                let cell = OWSTableItem.newCell()
                cell.selectionStyle = .none

                guard let self = self else { return cell }
                let button = OWSFlatButton.button(
                    title: OWSLocalizedString(
                        "BADGE_DETAILS_DONATE_TO_SIGNAL",
                        comment: "When viewing someone else's badge, you'll see a sheet. If they got the badge by donating, a \"Donate to Signal\" button will be shown. This is the text in that button."
                    ),
                    font: UIFont.dynamicTypeBody.semibold(),
                    titleColor: .white,
                    backgroundColor: .ows_accentBlue,
                    target: self,
                    selector: #selector(self.didTapDonate)
                )
                button.autoSetHeightUsingFont()
                button.cornerRadius = 8
                cell.contentView.addSubview(button)
                button.autoPinEdgesToSuperviewMargins()

                return cell
            })])
            buttonSection.hasBackground = false
            contents.add(buttonSection)
        }

    }

    @objc
    private func didTapDonate() {
        dismiss(animated: true) {
            if DonationUtilities.canDonateInAnyWay(
                tsAccountManager: DependenciesBridge.shared.tsAccountManager,
            ) {
                let frontVc = { CurrentAppContext().frontmostViewController() }

                let donateVc = DonateViewController(preferredDonateMode: .oneTime) { finishResult in
                    switch finishResult {
                    case let .completedDonation(donateSheet, receiptCredentialSuccessMode):
                        donateSheet.dismiss(animated: true) {
                            guard
                                let frontVc = frontVc(),
                                let badgeThanksSheetPresenter = BadgeThanksSheetPresenter.fromGlobalsWithSneakyTransaction(
                                    successMode: receiptCredentialSuccessMode
                                )
                            else { return }

                            Task {
                                await badgeThanksSheetPresenter.presentAndRecordBadgeThanks(
                                    fromViewController: frontVc
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
