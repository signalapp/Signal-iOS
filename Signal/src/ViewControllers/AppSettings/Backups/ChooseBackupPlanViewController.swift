//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

class ChooseBackupPlanViewController: HostingController<ChooseBackupPlanView> {
    enum PlanSelection {
        case free
        case paid
    }

    private let viewModel: ChooseBackupPlanViewModel

    init(
        paidPlanDisplayPrice: String,
        initialPlanSelection: PlanSelection
    ) {
        self.viewModel = ChooseBackupPlanViewModel(
            paidPlanDisplayPrice: paidPlanDisplayPrice,
            planSelection: initialPlanSelection
        )

        super.init(wrappedView: ChooseBackupPlanView(viewModel: viewModel))
    }
}

// MARK: -

private class ChooseBackupPlanViewModel: ObservableObject {
    typealias PlanSelection = ChooseBackupPlanViewController.PlanSelection

    let paidPlanDisplayPrice: String
    @Published var planSelection: PlanSelection

    init(
        paidPlanDisplayPrice: String,
        planSelection: PlanSelection
    ) {
        self.paidPlanDisplayPrice = paidPlanDisplayPrice
        self.planSelection = planSelection
    }
}

struct ChooseBackupPlanView: View {
    @ObservedObject private var viewModel: ChooseBackupPlanViewModel

    fileprivate init(viewModel: ChooseBackupPlanViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack {
            ScrollView {
                VStack {
                    Image("signal-backups-choose-plan")
                        .frame(width: 80, height: 80)

                    Spacer().frame(height: 8)

                    Text(OWSLocalizedString(
                        "CHOOSE_BACKUP_PLAN_TITLE",
                        comment: "Title for a view allowing users to choose a Backup plan."
                    ))
                    .font(.title.weight(.semibold))
                    .foregroundStyle(Color.Signal.label)

                    Spacer().frame(height: 12)

                    Text(OWSLocalizedString(
                        "CHOOSE_BACKUP_PLAN_SUBTITLE",
                        comment: "Subtitle for a view allowing users to choose a Backup plan."
                    ))
                    .appendLink(CommonStrings.learnMore) {
                        // TODO: [Backups] Open Support page
                    }
                    .foregroundStyle(Color.Signal.secondaryLabel)

                    Spacer().frame(height: 20)

                    PlanOptionView(
                        title: OWSLocalizedString(
                            "CHOOSE_BACKUP_PLAN_FREE_PLAN_TITLE",
                            comment: "Title for the free plan option, when choosing a Backup plan."
                        ),
                        subtitle: OWSLocalizedString(
                            "CHOOSE_BACKUP_PLAN_FREE_PLAN_SUBTITLE",
                            comment: "Subtitle for the free plan option, when choosing a Backup plan."
                        ),
                        bullets: [
                            PlanOptionView.BulletPoint(iconKey: "thread", text: OWSLocalizedString(
                                "CHOOSE_BACKUP_PLAN_BULLET_FULL_TEXT_BACKUP",
                                comment: "Text for a bullet point in a list of Backup features, describing that all text messages are included."
                            )),
                            PlanOptionView.BulletPoint(iconKey: "album-tilt", text: OWSLocalizedString(
                                "CHOOSE_BACKUP_PLAN_BULLET_RECENT_MEDIA_BACKUP",
                                comment: "Text for a bullet point in a list of Backup features, describing that recent media is included."
                            )),
                        ],
                        isSelected: viewModel.planSelection == .free,
                        onTap: {
                            viewModel.planSelection = .free
                        }
                    )

                    Spacer().frame(height: 16)

                    PlanOptionView(
                        title: String(
                            format: OWSLocalizedString(
                                "CHOOSE_BACKUP_PLAN_PAID_PLAN_TITLE",
                                comment: "Title for the paid plan option, when choosing a Backup plan. Embeds {{ the formatted monthly cost, as currency, of the paid plan }}."
                            ),
                            viewModel.paidPlanDisplayPrice
                        ),
                        subtitle: OWSLocalizedString(
                            "CHOOSE_BACKUP_PLAN_PAID_PLAN_SUBTITLE",
                            comment: "Subtitle for the paid plan option, when choosing a Backup plan."
                        ),
                        bullets: [
                            PlanOptionView.BulletPoint(iconKey: "thread", text: OWSLocalizedString(
                                "CHOOSE_BACKUP_PLAN_BULLET_FULL_TEXT_BACKUP",
                                comment: "Text for a bullet point in a list of Backup features, describing that all text messages are included."
                            )),
                            PlanOptionView.BulletPoint(iconKey: "album-tilt", text: OWSLocalizedString(
                                "CHOOSE_BACKUP_PLAN_BULLET_FULL_MEDIA_BACKUP",
                                comment: "Text for a bullet point in a list of Backup features, describing that all media is included."
                            )),
                            PlanOptionView.BulletPoint(iconKey: "data", text: OWSLocalizedString(
                                "CHOOSE_BACKUP_PLAN_BULLET_STORAGE_AMOUNT",
                                comment: "Text for a bullet point in a list of Backup features, describing the amount of included storage."
                            )),
                        ],
                        isSelected: viewModel.planSelection == .paid,
                        onTap: {
                            viewModel.planSelection = .paid
                        }
                    )
                }
                .padding(.horizontal, 24)
            }

            Button {
                // TODO: Implement
            } label: {
                let text = switch viewModel.planSelection {
                case .free:
                    CommonStrings.continueButton
                case .paid:
                    String(
                        format: OWSLocalizedString(
                            "CHOOSE_BACKUP_PLAN_SUBSCRIBE_PAID_BUTTON_TEXT",
                            comment: "Text for a button that will subscribe the user to the paid Backup plan. Embeds {{ the formatted monthly cost, as currency, of the paid plan }}."
                        ),
                        viewModel.paidPlanDisplayPrice
                    )
                }

                Text(text)
                    .foregroundStyle(.white)
                    .font(.headline)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .background(Color.Signal.ultramarine)
            .cornerRadius(12)
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.Signal.groupedBackground)
    }
}

// MARK: -

private struct PlanOptionView: View {
    struct BulletPoint {
        let iconKey: String
        let text: String
    }

    let title: String
    let subtitle: String
    let bullets: [BulletPoint]
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    Text(title).font(.headline)
                    Text(subtitle).foregroundStyle(Color.Signal.secondaryLabel)

                    ForEach(bullets, id: \.iconKey) { bullet in
                        Label {
                            Text(bullet.text).font(.subheadline)
                        } icon: {
                            Image(bullet.iconKey)
                                .foregroundStyle(
                                    isSelected
                                    ? Color.Signal.ultramarine
                                    : Color.Signal.label
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
                        lineWidth: isSelected ? 3 : 0
                    )
            }
            .shadow(
                color: isSelected ? .black.opacity(0.12) : .clear,
                radius: 8,
                y: 2
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: -

#if DEBUG

#Preview {
    NavigationView {
        ChooseBackupPlanView(viewModel: ChooseBackupPlanViewModel(
            paidPlanDisplayPrice: "$2.99",
            planSelection: .free
        ))
    }
}

#endif
