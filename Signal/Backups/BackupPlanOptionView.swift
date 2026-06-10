//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SwiftUI

struct BackupPlanOptionView: View {
    struct BulletPoint {
        let icon: UIImage
        let text: String
    }

    let title: String
    let subtitle: String
    let bullets: [BulletPoint]
    let bulletIconTintColor: UIColor
    let isCurrentPlan: Bool
    let isSelected: Bool
    let showSelectionCircle: Bool

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                if isCurrentPlan {
                    Label(
                        OWSLocalizedString(
                            "CHOOSE_BACKUP_PLAN_CURRENT_PLAN_LABEL",
                            comment: "A label indicating that a given Backup plan option is what the user has already enabled.",
                        ),
                        systemImage: "checkmark",
                    )
                    .font(.footnote)
                    .foregroundStyle(Color.Signal.secondaryLabel)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                    .background {
                        Capsule().fill(Color.Signal.secondaryFill)
                    }
                }

                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                Text(subtitle).foregroundStyle(Color.Signal.secondaryLabel)

                ForEach(bullets, id: \.text) { bullet in
                    Label {
                        Text(bullet.text).font(.subheadline)
                    } icon: {
                        Image(uiImage: bullet.icon)
                            .foregroundStyle(
                                Color(bulletIconTintColor),
                            )
                    }
                    .padding(.leading, 20)
                    .padding(.vertical, 2)
                }
            }

            Spacer()

            Group {
                if showSelectionCircle, isSelected {
                    Circle()
                        .fill(Color.Signal.ultramarine)
                        .overlay {
                            Image(systemName: "checkmark")
                                .resizable()
                                .foregroundColor(.white)
                                .padding(6)
                        }
                } else if showSelectionCircle {
                    Circle()
                        .stroke(Color.Signal.secondaryLabel, lineWidth: 2)
                        .opacity(0.3)
                }
            }
            .frame(width: 24, height: 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 20)
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .background(Color.Signal.secondaryGroupedBackground)
        .cornerRadius(16)
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    Color.Signal.ultramarine,
                    lineWidth: isSelected ? 3 : 0,
                )
        }
        .shadow(
            color: isSelected ? .black.opacity(0.12) : .clear,
            radius: 8,
            y: 2,
        )
    }
}

// MARK: -

struct BackupPlanFreeOptionView: View {
    let freeMediaTierDays: UInt64
    let bulletIconTintColor: UIColor
    let isCurrentPlan: Bool
    let isSelected: Bool
    let showSelectionCircle: Bool

    var body: some View {
        BackupPlanOptionView(
            title: OWSLocalizedString(
                "CHOOSE_BACKUP_PLAN_FREE_PLAN_TITLE",
                comment: "Title for the free plan option, when choosing a Backup plan.",
            ),
            subtitle: String.localizedStringWithFormat(
                OWSLocalizedString(
                    "CHOOSE_BACKUP_PLAN_FREE_PLAN_SUBTITLE_%d",
                    tableName: "PluralAware",
                    comment: "Subtitle for the free plan option, when choosing a Backup plan. Embeds {{ the number of days that files are available, e.g. '45' }}.",
                ),
                freeMediaTierDays,
            ),
            bullets: [
                BackupPlanOptionView.BulletPoint(icon: .thread, text: OWSLocalizedString(
                    "CHOOSE_BACKUP_PLAN_BULLET_FULL_TEXT_BACKUP",
                    comment: "Text for a bullet point in a list of Backup features, describing that all text messages are included.",
                )),
                BackupPlanOptionView.BulletPoint(icon: .albumTilt, text: String.localizedStringWithFormat(
                    OWSLocalizedString(
                        "CHOOSE_BACKUP_PLAN_BULLET_RECENT_MEDIA_BACKUP_%d",
                        tableName: "PluralAware",
                        comment: "Text for a bullet point in a list of Backup features, describing that recent media is included. Embeds {{ the number of days that files are available, e.g. '45' }}.",
                    ),
                    freeMediaTierDays,
                )),
            ],
            bulletIconTintColor: bulletIconTintColor,
            isCurrentPlan: isCurrentPlan,
            isSelected: isSelected,
            showSelectionCircle: showSelectionCircle,
        )
    }
}

// MARK: -

struct BackupPlanPaidOptionView: View {
    let storeKitAvailability: BackupPlanUpsellConfiguration.StoreKitAvailability
    let storageAllowanceBytes: UInt64
    let bulletIconTintColor: UIColor
    let isCurrentPlan: Bool
    let isSelected: Bool
    let showSelectionCircle: Bool

    var storageAllowanceBytesFormatted: String {
        storageAllowanceBytes.formatted(.owsByteCount(
            fudgeBase2ToBase10: true,
            zeroPadFractionDigits: false,
        ))
    }

    var body: some View {
        BackupPlanOptionView(
            title: {
                switch storeKitAvailability {
                case .available(let paidPlanDisplayPrice):
                    String.nonPluralLocalizedStringWithFormat(
                        OWSLocalizedString(
                            "CHOOSE_BACKUP_PLAN_PAID_PLAN_TITLE",
                            comment: "Title for the paid plan option, when choosing a Backup plan. Embeds {{ the formatted monthly cost, as currency, of the paid plan }}.",
                        ),
                        paidPlanDisplayPrice,
                    )
                case .unavailableForTesters:
                    OWSLocalizedString(
                        "CHOOSE_BACKUP_PLAN_PAID_PLAN_NO_PURCHASES_TITLE",
                        comment: "Title for the paid plan option, when choosing a Backup plan as a tester.",
                    )
                }
            }(),
            subtitle: OWSLocalizedString(
                "CHOOSE_BACKUP_PLAN_PAID_PLAN_SUBTITLE",
                comment: "Subtitle for the paid plan option, when choosing a Backup plan.",
            ),
            bullets: [
                BackupPlanOptionView.BulletPoint(
                    icon: .thread,
                    text: OWSLocalizedString(
                        "CHOOSE_BACKUP_PLAN_BULLET_FULL_TEXT_AND_MEDIA_BACKUP",
                        comment: "Text for a bullet point in a list of Backup features, describing that all text messages and media are included.",
                    ),
                ),
                BackupPlanOptionView.BulletPoint(
                    icon: .data,
                    text: String.nonPluralLocalizedStringWithFormat(
                        OWSLocalizedString(
                            "CHOOSE_BACKUP_PLAN_BULLET_STORAGE_AMOUNT",
                            comment: "Text for a bullet point in a list of Backup features, describing the amount of included storage. Embeds {{ the amount of storage preformatted as a localized byte count, e.g. '100 GB' }}.",
                        ),
                        storageAllowanceBytesFormatted,
                    ),
                ),
                BackupPlanOptionView.BulletPoint(
                    icon: .devicePhone,
                    text: OWSLocalizedString(
                        "CHOOSE_BACKUP_PLAN_BULLET_SAVE_DEVICE_STORAGE",
                        comment: "Text for a bullet point in a list of Backup features, describing that the paid Backup plan can save on-device storage space.",
                    ),
                ),
                BackupPlanOptionView.BulletPoint(
                    icon: .heart,
                    text: OWSLocalizedString(
                        "CHOOSE_BACKUP_PLAN_BULLET_THANKS_FOR_SUPPORTING_SIGNAL",
                        comment: "Text for a bullet point in a list of Backup features, thanking the user for supporting Signal by subscribing to the paid Backup plan.",
                    ),
                ),
            ],
            bulletIconTintColor: bulletIconTintColor,
            isCurrentPlan: isCurrentPlan,
            isSelected: isSelected,
            showSelectionCircle: showSelectionCircle,
        )
    }
}
