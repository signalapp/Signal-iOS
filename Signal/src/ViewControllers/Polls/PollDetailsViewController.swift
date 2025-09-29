//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import LibSignalClient
import SignalUI
import SwiftUI

final class PollDetailsViewController: HostingController<PollDetailsView>, ObservableObject {
    private let viewModel: PollDetailsViewModel

    init(poll: OWSPoll) {
        self.viewModel = PollDetailsViewModel()
        super.init(wrappedView: PollDetailsView(poll: poll, viewModel: viewModel))
        viewModel.actionsDelegate = self
    }
}

extension PollDetailsViewController: PollDetailsViewModel.ActionsDelegate {
    fileprivate func onDismiss() {
        dismiss(animated: true)
    }

    func pollTerminate() {
        // TODO: implement
    }
}

final private class PollDetailsViewModel {
    protocol ActionsDelegate: AnyObject {
        func onDismiss()
        func pollTerminate()
    }

    weak var actionsDelegate: ActionsDelegate?

    func onDismiss() {
        actionsDelegate?.onDismiss()
    }

    func pollTerminate() {
        actionsDelegate?.pollTerminate()
    }
}

struct PollDetailsView: View {
    fileprivate let viewModel: PollDetailsViewModel
    private var poll: OWSPoll

    fileprivate init(poll: OWSPoll, viewModel: PollDetailsViewModel) {
        self.poll = poll
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(OWSLocalizedString("POLL_DETAILS_TITLE", comment: "Title of poll details pane"))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .center)
                HStack {
                    Button(CommonStrings.doneButton, action: {
                        viewModel.onDismiss()
                    })
                    .foregroundColor(Color.Signal.label)
                    .padding()
                    Spacer()
                }
            }
            .background(Color.Signal.secondaryBackground)
            SignalList {
                SignalSection {
                    Text(poll.question)
                        .font(.body)
                        .foregroundColor(Color.Signal.label)
                }

                // TODO: only show for poll creator
                if !poll.isEnded {
                    SignalSection {
                        Button {
                            viewModel.pollTerminate()
                        } label: {
                            Label {
                                Text(OWSLocalizedString("POLL_DETAILS_END_POLL", comment: "Label for button to end a poll"))
                                    .font(.body)
                                    .foregroundColor(Color.Signal.label)
                            } icon: {
                                Image(Theme.iconName(.pollStop))
                            }
                        }
                    }
                }

                ForEach(poll.sortedOptions()) { option in
                    SignalSection {
                        ForEach(option.acis, id: \.self) { aci in
                            ContactRow(address: SignalServiceAddress(aci))
                                .padding(.vertical, 1)
                                .padding(.horizontal, 4)
                        }
                    } header: {
                        // TODO: add star icon to winning option if poll is ended
                        HStack {
                            Text(option.text)
                                .font(.body)
                                .fontWeight(.medium)
                            Spacer()
                            Text(
                                String(
                                    format: OWSLocalizedString(
                                        "POLL_VOTE_COUNT",
                                        tableName: "PluralAware",
                                        comment: "Count indicating number of votes for this option. Embeds {{number of votes}}"
                                    ),
                                    option.acis.count
                                )
                            )
                            .font(.body)
                        }
                    }
                }
            }
        }
    }

    struct ContactRow: UIViewRepresentable {
        let address: SignalServiceAddress

        func updateUIView(_ uiView: ManualStackView, context: Context) {
        }

        func makeUIView(context: Context) -> ManualStackView {
            return addressCell(address: address) ?? ManualStackView(name: "??")
        }

        private func addressCell(address: SignalServiceAddress) -> ManualStackView? {
            let cell = ContactCellView()
            let config = ContactCellConfiguration(address: address, localUserDisplayMode: .noteToSelf)
            config.avatarSizeClass = .twentyEight

            SSKEnvironment.shared.databaseStorageRef.read { transaction in
                let isSystemContact = SSKEnvironment.shared.contactManagerRef.fetchSignalAccount(for: address, transaction: transaction) != nil
                config.shouldShowContactIcon = isSystemContact

                cell.configure(configuration: config, transaction: transaction)
            }
            return cell
        }
    }
}

#Preview {
    let poll = OWSPoll(
        pollId: 1,
        question: "What is your favorite color?",
        options: ["Red", "Blue", "Yellow"],
        allowsMultiSelect: false,
        votes: [:],
        isEnded: false
    )

    PollDetailsView(poll: poll, viewModel: PollDetailsViewModel())
}
