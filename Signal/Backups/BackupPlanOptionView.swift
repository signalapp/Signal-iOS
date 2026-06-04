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
    let isCurrentPlan: Bool
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
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
                                    isSelected
                                        ? Color.Signal.ultramarine
                                        : Color.Signal.label,
                                )
                        }
                        .padding(.leading, 20)
                        .padding(.vertical, 2)
                    }
                }

                Spacer()

                Group {
                    if isSelected {
                        Circle()
                            .fill(Color.Signal.ultramarine)
                            .overlay {
                                Image(systemName: "checkmark")
                                    .resizable()
                                    .foregroundColor(.white)
                                    .padding(6)
                            }
                    } else {
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
        .buttonStyle(.plain)
    }
}
