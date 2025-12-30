//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

class BackupOnboardingIntroViewController: HostingController<BackupOnboardingIntroView> {
    init(
        onContinue: @escaping () -> Void,
        onNotNow: @escaping () -> Void,
    ) {
        super.init(wrappedView: BackupOnboardingIntroView(
            onContinue: onContinue,
            onNotNow: onNotNow,
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
                comment: "Bullet point on a view introducing Backups during an onboarding flow.",
            ),
        ),
        BulletPoint(
            image: .checkSquare,
            text: OWSLocalizedString(
                "BACKUP_ONBOARDING_INTRO_BULLET_2",
                comment: "Bullet point on a view introducing Backups during an onboarding flow.",
            ),
        ),
        BulletPoint(
            image: .trash,
            text: OWSLocalizedString(
                "BACKUP_ONBOARDING_INTRO_BULLET_3",
                comment: "Bullet point on a view introducing Backups during an onboarding flow.",
            ),
        ),
    ]

    private var titleString: AttributedString {
        var attributedString = AttributedString("BETA")
        attributedString.backgroundColor = Color.Signal.secondaryFill
        return attributedString
    }

    var body: some View {
        ScrollableContentPinnedFooterView {
            HStack(spacing: 12) {
                Image(Theme.iconName(.info))

                Text(
                    OWSLocalizedString(
                        "BACKUP_SETTINGS_BETA_NOTICE_HEADER",
                        comment: "Notice that backups is a beta feature",
                    ),
                )
                .font(.footnote)
                .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .foregroundColor(Color.Signal.label)
            .padding(.vertical, 16)
            .padding(.leading, 16)
            .padding(.trailing, 11)
            .background(Color.Signal.quaternaryFill)
            .cornerRadius(12)
            .padding(.horizontal, 20)

            VStack {
                Spacer().frame(height: 20)

                Image(.backupsLogo)
                    .frame(width: 80, height: 80)

                Spacer().frame(height: 16)
                HStack {
                    Text(OWSLocalizedString(
                        "BACKUP_ONBOARDING_INTRO_TITLE",
                        comment: "Title for a view introducing Backups during an onboarding flow.",
                    ))
                    .font(Font(UIFont.dynamicTypeFont(ofStandardSize: 26)))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Signal.label)

                    Text(CommonStrings.betaLabel)
                        .font(.caption)
                        .bold()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(
                                Color.Signal.secondaryFill),
                        )
                        .foregroundStyle(Color.Signal.label)
                }
                .padding(.horizontal, 32)
                .multilineTextAlignment(.center)

                Spacer().frame(height: 12)

                Text(OWSLocalizedString(
                    "BACKUP_ONBOARDING_INTRO_SUBTITLE",
                    comment: "Subtitle for a view introducing Backups during an onboarding flow.",
                ))
                .font(.body)
                .foregroundStyle(Color.Signal.secondaryLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

                Spacer().frame(height: 32)

                VStack(alignment: .leading, spacing: 26) {
                    ForEach(bulletPoints) { bulletPoint in
                        HStack {
                            Label {
                                Text(bulletPoint.text)
                            } icon: {
                                Image(uiImage: bulletPoint.image)
                            }

                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 56)
                .frame(maxWidth: .infinity)
                .foregroundStyle(Color.Signal.label)
                .padding(.horizontal)
            }
        } pinnedFooter: {
            Button {
                onContinue()
            } label: {
                Text(CommonStrings.continueButton)
            }
            .buttonStyle(Registration.UI.LargePrimaryButtonStyle())
            .padding(.horizontal, 40)

            Spacer().frame(height: 16)

            Button {
                onNotNow()
            } label: {
                Text(CommonStrings.notNowButton)
            }
            .buttonStyle(Registration.UI.LargeSecondaryButtonStyle())
            .padding(.horizontal, 40)
        }
        .background(Color.Signal.groupedBackground)
    }
}

// MARK: -

#if DEBUG

@available(iOS 17, *)
#Preview {
    SheetPreviewViewController(sheet: OWSNavigationController(rootViewController: BackupOnboardingIntroViewController(
        onContinue: { print("Continuing...!") },
        onNotNow: { print("Not now...!") },
    )))
}

#endif
