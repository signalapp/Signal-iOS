//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

final class BackupOnboardingIntroViewController: HostingController<BackupOnboardingIntroView> {
    init(
        onContinue: @escaping () -> Void,
        onNotNow: @escaping () -> Void,
    ) {
        super.init(wrappedView: BackupOnboardingIntroView(
            onContinue: onContinue,
            onNotNow: onNotNow
        ))

        OWSTableViewController2.removeBackButtonText(viewController: self)
    }
}

// MARK: -

struct BackupOnboardingIntroView: View {
    private struct BulletPoint: Identifiable {
        let image: UIImage
        let text: String

        var id: String { text }
    }

    fileprivate let onContinue: () -> Void
    fileprivate let onNotNow: () -> Void

    private let bulletPoints: [BulletPoint] = [
        BulletPoint(
            image: .lock,
            text: OWSLocalizedString(
                "BACKUP_ONBOARDING_INTRO_BULLET_1",
                comment: "Bullet point on a view introducing Backups during an onboarding flow."
            )
        ),
        BulletPoint(
            image: .checkSquare,
            text: OWSLocalizedString(
                "BACKUP_ONBOARDING_INTRO_BULLET_2",
                comment: "Bullet point on a view introducing Backups during an onboarding flow."
            )
        ),
        BulletPoint(
            image: .trash,
            text: OWSLocalizedString(
                "BACKUP_ONBOARDING_INTRO_BULLET_3",
                comment: "Bullet point on a view introducing Backups during an onboarding flow."
            )
        ),
    ]

    var body: some View {
        ScrollableContentPinnedFooterView {
            VStack {
                HStack {
                    Image(uiImage: Theme.iconImage(.info))
                        .frame(width: 25, height: 40)

                    Text(OWSLocalizedString(
                        "BACKUP_SETTINGS_BETA_NOTICE_HEADER",
                        comment: "Notice that backups is a beta feature")
                    )
                    .font(.footnote)
                    .multilineTextAlignment(.leading)
                }
                .foregroundColor(Color.Signal.label)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .background(Color.Signal.quaternaryFill)
                .cornerRadius(12)
            }
            .padding(.horizontal, 10)

            VStack {
                Spacer().frame(height: 20)

                Image(.backupsLogo)
                    .frame(width: 80, height: 80)

                Spacer().frame(height: 16)
                HStack {
                    Text(OWSLocalizedString(
                        "BACKUP_ONBOARDING_INTRO_TITLE",
                        comment: "Title for a view introducing Backups during an onboarding flow."
                    ))
                    .font(.title)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Signal.label)

                    Text(CommonStrings.betaLabel)
                        .font(.caption)
                        .bold()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(
                            Color.Signal.secondaryFill)
                        )
                        .foregroundStyle(Color.Signal.label)
                }

                Spacer().frame(height: 12)

                Text(OWSLocalizedString(
                    "BACKUP_ONBOARDING_INTRO_SUBTITLE",
                    comment: "Subtitle for a view introducing Backups during an onboarding flow."
                ))
                .font(.body)
                .foregroundStyle(Color.Signal.secondaryLabel)

                Spacer().frame(height: 32)

                VStack(alignment: .leading, spacing: 24) {
                    ForEach(bulletPoints) { bulletPoint in
                        Label {
                            Text(bulletPoint.text)
                        } icon: {
                            Image(uiImage: bulletPoint.image)
                        }
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(Color.Signal.label)
                        .padding(.horizontal, 20) // Extra inset in case of wrap
                    }
                }
            }
            .padding(.horizontal, 48)
        } pinnedFooter: {
            Button {
                onContinue()
            } label: {
                Text(CommonStrings.continueButton)
                    .foregroundStyle(.white)
                    .font(.headline)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(Color.Signal.ultramarine)
            }
            .buttonStyle(.plain)
            .cornerRadius(12)
            .padding(.horizontal, 40)

            Spacer().frame(height: 16)

            Button {
                onNotNow()
            } label: {
                Text(CommonStrings.notNowButton)
                    .foregroundStyle(Color.Signal.ultramarine)
                    .font(.headline)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
        }
        .multilineTextAlignment(.center)
        .background(Color.Signal.groupedBackground)
    }
}

// MARK: -

#if DEBUG

#Preview {
    BackupOnboardingIntroView(
        onContinue: { print("Continuing...!") },
        onNotNow: { print("Not now...!") }
    )
}

#endif
