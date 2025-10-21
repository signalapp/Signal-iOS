//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import LibSignalClient
import SignalUI
import SwiftUI

protocol PollDetailsViewControllerDelegate: AnyObject {
    func terminatePoll(poll: OWSPoll)
}

class PollDetailsViewController: HostingController<PollDetailsView> {
    private let viewModel: PollDetailsViewModel
    weak var delegate: PollDetailsViewControllerDelegate?
    private let poll: OWSPoll

    init(poll: OWSPoll) {
        self.viewModel = PollDetailsViewModel()
        self.poll = poll
        super.init(wrappedView: PollDetailsView(poll: poll, viewModel: viewModel))
        viewModel.actionsDelegate = self
    }
}

extension PollDetailsViewController: PollDetailsViewModel.ActionsDelegate {
    fileprivate func onDismiss() {
        dismiss(animated: true)
    }

    func pollTerminate() {
        delegate?.terminatePoll(poll: self.poll)
        dismiss(animated: true)
    }
}

private class PollDetailsViewModel {
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

    var titleString: String {
        if poll.isEnded {
            return OWSLocalizedString("POLL_RESULTS_TITLE", comment: "Title of poll details pane when poll is ended")
        }
        return OWSLocalizedString("POLL_DETAILS_TITLE", comment: "Title of poll details pane")
    }

    fileprivate init(poll: OWSPoll, viewModel: PollDetailsViewModel) {
        self.poll = poll
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 0) {
            SignalList {
                SignalSection {
                    Text(poll.question)
                        .font(.body)
                        .foregroundColor(Color.Signal.label)
                }

                if !poll.isEnded, poll.ownerIsLocalUser {
                    SignalSection {
                        Button {
                            viewModel.pollTerminate()
                        } label: {
                            Label {
                                Text(OWSLocalizedString("POLL_DETAILS_END_POLL", comment: "Label for button to end a poll"))
                                    .font(.body)
                                    .foregroundColor(Color.Signal.label)
                            } icon: {
                                Image(uiImage: Theme.iconImage(.pollStop))
                            }
                            .foregroundColor(Color.Signal.label)
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
                        if option.acis.count == 0 {
                            Text(OWSLocalizedString(
                                "POLL_NO_VOTES",
                                comment: "String to display when a poll has no votes"
                            ))
                            .font(.body)
                            .foregroundColor(Color.Signal.secondaryLabel)
                        }
                    } header: {
                        // TODO: add star icon to winning option if poll is ended
                        HStack {
                            Text(option.text)
                                .font(.body)
                                .fontWeight(.medium)
                            Spacer()
                            if option.acis.count > 0 {
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
        .navigationTitle(titleString)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if #available(iOS 26.0, *) {
                    Button(action: {
                        viewModel.onDismiss()
                    }) {
                        Image(Theme.iconName(.xBold))
                    }
                    .accessibilityLabel(CommonStrings.doneButton)
                } else {
                    Button(CommonStrings.doneButton, action: {
                        viewModel.onDismiss()
                    })
                    .foregroundColor(Color.Signal.label)
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
            let config = ContactCellConfiguration(address: address, localUserDisplayMode: .asLocalUser)
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
        interactionId: 1,
        question: "What is your favorite color?",
        options: ["Red", "Blue", "Yellow"],
        localUserPendingState: [:],
        allowsMultiSelect: false,
        votes: [:],
        isEnded: false,
        ownerIsLocalUser: false
    )

    PollDetailsView(poll: poll, viewModel: PollDetailsViewModel())
}
