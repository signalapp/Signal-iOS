//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

class BadgeDetailsSheet: HeroSheetViewController {
    enum Owner: Equatable {
        // TODO: Eventually we won't need a short name for self, the server will provide copy for us.
        case local(shortName: String)
        case remote(shortName: String)

        func formattedDescription(for badge: ProfileBadge) -> String {
            switch self {
            case .local(let shortName), .remote(let shortName):
                badge.localizedDescriptionFormatString.replacingOccurrences(
                    of: "{short_name}",
                    with: shortName,
                )
            }
        }

        var isLocal: Bool {
            switch self {
            case .local: return true
            case .remote: return false
            }
        }
    }

    // TODO: support initializing with a list of available badges and paging between them
    init(focusedBadge: ProfileBadge, owner: Owner) {
        let remoteSupporterName: String? = {
            guard
                focusedBadge.category == .donor,
                !GiftBadgeIds.contains(focusedBadge.id),
                case let .remote(name) = owner
            else { return nil }
            return name
        }()

        let title: String
        if let remoteSupporterName {
            let format = OWSLocalizedString(
                "BADGE_DETAILS_TITLE_FOR_SUPPORTER",
                comment: "When viewing someone else's donor badge, you'll see a sheet. This is the title on that sheet. Embeds {badge owner's short name}",
            )
            title = String.nonPluralLocalizedStringWithFormat(format, remoteSupporterName)
        } else {
            title = focusedBadge.localizedName
        }

        let primaryButton: HeroSheetViewController.Button? = {
            guard !owner.isLocal else {
                return nil
            }
            return HeroSheetViewController.Button(
                title: OWSLocalizedString(
                    "BADGE_DETAILS_DONATE_TO_SIGNAL",
                    comment: "When viewing someone else's badge, you'll see a sheet. If they got the badge by donating, a \"Donate to Signal\" button will be shown. This is the text in that button.",
                ),
                action: { vc in
                    Self.donate(from: vc)
                },
            )
        }()

        super.init(
            hero: .image(focusedBadge.assets?.universal160 ?? UIImage()),
            title: title,
            body: owner.formattedDescription(for: focusedBadge),
            primaryButton: primaryButton,
        )
    }

    private static func donate(from vc: UIViewController) {
        vc.dismiss(animated: true) {
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
