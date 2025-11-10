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

    func presentContactSheet(address: SignalServiceAddress) {
        guard address.isValid else {
            owsFailDebug("Invalid address.")
            return
        }
        ProfileSheetSheetCoordinator(
            address: address,
            groupViewHelper: nil,
            spoilerState: SpoilerRenderState()
        )
        .presentAppropriateSheet(from: self)
    }
}

private class PollDetailsViewModel {
    protocol ActionsDelegate: AnyObject {
        func onDismiss()
        func pollTerminate()
        func presentContactSheet(address: SignalServiceAddress)
    }

    weak var actionsDelegate: ActionsDelegate?

    func onDismiss() {
        actionsDelegate?.onDismiss()
    }

    func pollTerminate() {
        OWSActionSheets.showConfirmationAlert(
            title: OWSLocalizedString(
                "POLL_END_CONFIRMATION",
                comment: "Title for an action sheet confirming the user wants end a poll."
            ),
            message: OWSLocalizedString(
                "POLL_END_CONFIRMATION_MESSAGE",
                comment: "Message for an action sheet confirming the user wants to end a poll."
            ),
            proceedTitle: CommonStrings.okButton,
            proceedAction: { [weak self] _ in
                self?.actionsDelegate?.pollTerminate()
            }
        )
    }

    func presentContactSheet(address: SignalServiceAddress) {
        actionsDelegate?.presentContactSheet(address: address)
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
                } header: {
                    Text(
                        OWSLocalizedString(
                            "POLL_QUESTION_LABEL",
                            comment: "Header for the poll question text box when making a new poll"
                        )
                    )
                }
                if #unavailable(iOS 26) {
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
                }

                let maxVotes = poll.maxVoteCount()
                ForEach(poll.sortedOptions()) { option in
                    SignalSection {
                        ForEach(option.acis, id: \.self) { aci in
                            ContactRow(
                                address: SignalServiceAddress(aci),
                                onTap: { address in
                                    viewModel.presentContactSheet(address: address)
                                }
                            )
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
                        HStack {
                            Text(option.text)
                                .font(.body)
                                .fontWeight(.medium)
                            Spacer()
                            if option.acis.count > 0 {
                                if poll.isEnded && option.acis.count == maxVotes {
                                    Image("poll-win")
                                }
                                Text(
                                    String.localizedStringWithFormat(
                                        OWSLocalizedString(
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if #available(iOS 26.0, *) {
                if !poll.isEnded, poll.ownerIsLocalUser {
                    Button {
                        viewModel.pollTerminate()
                    } label: {
                        Text(OWSLocalizedString("POLL_DETAILS_END_POLL", comment: "Label for button to end a poll"))
                    }
                    .buttonStyle(Registration.UI.LargePrimaryButtonStyle())
                    .padding()
                }
            }
        }
        .navigationTitle(titleString)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if #available(iOS 26.0, *) {
                    Button(action: {
                        viewModel.onDismiss()
                    }) {
                        Image(Theme.iconName(.x26))
                    }
                    .accessibilityLabel(CommonStrings.doneButton)
                    .foregroundColor(Color.Signal.label)
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
        var onTap: ((SignalServiceAddress) -> Void)

        func updateUIView(_ uiView: ManualStackView, context: Context) {
        }

        func makeUIView(context: Context) -> ManualStackView {
            let contactView = addressCell(address: address) ?? ManualStackView(name: "??")
            contactView.addTapGesture {
                onTap(address)
            }
            return contactView
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
