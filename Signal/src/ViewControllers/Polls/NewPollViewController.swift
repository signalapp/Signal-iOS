//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import LibSignalClient
import SignalUI
import SwiftUI

public protocol PollSendDelegate: AnyObject {
    func sendPoll(question: String, options: [String], allowMultipleVotes: Bool)
}

class NewPollViewController: HostingController<NewPollView> {
    public weak var sendDelegate: PollSendDelegate?
    private let viewModel: NewPollViewModel

    init() {
        self.viewModel = NewPollViewModel()
        super.init(wrappedView: NewPollView(viewModel: viewModel))
        viewModel.actionsDelegate = self
    }
}

extension NewPollViewController: NewPollViewModel.ActionsDelegate {
    fileprivate func onDismiss() {
        dismiss(animated: true)
    }

    fileprivate func onSend(
        pollOptions: [String],
        question: String,
        allowMultipleVotes: Bool
    ) {
        sendDelegate?.sendPoll(
            question: question,
            options: pollOptions,
            allowMultipleVotes: allowMultipleVotes
        )

        dismiss(animated: true)
    }

    fileprivate func showToast(
        hasQuestion: Bool,
        hasEnoughOptions: Bool,
    ) {
        var toast: ToastController
        if !hasQuestion && !hasEnoughOptions {
            toast = ToastController(text: OWSLocalizedString(
                "POLL_CREATE_ERROR_TOAST_NO_QUESTION_OR_ENOUGH_OPTIONS",
                comment: "Toast telling user to add options and question to poll."
            ))
        } else if !hasQuestion {
            toast = ToastController(text: OWSLocalizedString(
                "POLL_CREATE_ERROR_TOAST_NO_QUESTION",
                comment: "Toast telling user to add a question to poll."
            ))
        } else {
            toast = ToastController(text: OWSLocalizedString(
                "POLL_CREATE_ERROR_TOAST_NOT_ENOUGH_OPTIONS",
                comment: "Toast telling user to add more options to poll."
            ))
        }

        toast.presentToastView(from: .bottom, of: view, inset: view.safeAreaInsets.bottom + 8)
    }
}

private class NewPollViewModel {
    protocol ActionsDelegate: AnyObject {
        func onDismiss()
        func onSend(
            pollOptions: [String],
            question: String,
            allowMultipleVotes: Bool
        )
        func showToast(
            hasQuestion: Bool,
            hasEnoughOptions: Bool,
        )
    }

    weak var actionsDelegate: ActionsDelegate?

    func onDismiss() {
        actionsDelegate?.onDismiss()
    }

    func onSend(
        pollOptions: [String],
        question: String,
        allowMultipleVotes: Bool
    ) {
        actionsDelegate?.onSend(
            pollOptions: pollOptions,
            question: question,
            allowMultipleVotes: allowMultipleVotes
        )
    }

    func showToast(
        hasQuestion: Bool,
        hasEnoughOptions: Bool,
    ) {
        actionsDelegate?.showToast(
            hasQuestion: hasQuestion,
            hasEnoughOptions: hasEnoughOptions
        )
    }
}

struct NewPollView: View {
    struct NewOption: Identifiable, Equatable {
        let id = UUID()
        var text: String
    }

    fileprivate let viewModel: NewPollViewModel
    @State var pollQuestion: String = ""
    @State var pollOptions: [NewOption] = [NewOption(text: ""), NewOption(text: "")]
    @State var allowMultipleVotes: Bool = false

    @FocusState private var focusedItemID: UUID?

    let characterLimit: Int = 100

    fileprivate init(viewModel: NewPollViewModel) {
        self.viewModel = viewModel
    }

    struct OptionRow: View {
        @Binding var option: NewOption
        let optionIndex: Int
        let totalCount: Int
        var body: some View {
            HStack {
                TextField(localizedOptionPlaceholderText(index: optionIndex + 1), text: Binding(
                    get: { return option.text },
                    set: { option.text = $0 })
                )

                if !option.text.isEmpty && totalCount > 2 {
                    Spacer()
                    Image("poll-drag")
                }
            }
        }

        private func localizedOptionPlaceholderText(index: Int) -> String {
            let locText = OWSLocalizedString(
                "POLL_OPTION_PLACEHOLDER_PREFIX",
                comment: "Placeholder text for an option row when creating a poll. This will have a number appended to it (Option 1, Option 2)"
            )

            let formatter: NumberFormatter = {
                let f = NumberFormatter()
                f.numberStyle = .decimal
                return f
            }()

            let localizedNumber = formatter.string(from: NSNumber(value: index))!

            return locText + " " + localizedNumber
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SignalList {
                SignalSection {
                    TextField(
                        OWSLocalizedString(
                            "POLL_QUESTION_PLACEHOLDER_TEXT",
                            comment: "Placeholder text for poll question"
                        ),
                        text: $pollQuestion
                    )
                    .onChange(of: pollQuestion) { newText in
                        if newText.count > characterLimit {
                            pollQuestion = String(newText.prefix(characterLimit))
                        }
                    }
                } header: {
                    Text(
                        OWSLocalizedString(
                            "POLL_QUESTION_LABEL",
                            comment: "Header for the poll question text box when making a new poll"
                        )
                    )
                    .font(.headline)
                    .foregroundColor(Color.Signal.label)
                }
                SignalSection {
                    ForEach($pollOptions) { $option in
                        let index = indexForOption(option: option)
                        OptionRow(option: $option, optionIndex: index, totalCount: pollOptions.count)
                            .onChange(of: option.text) { newText in
                                if newText.count > characterLimit {
                                    option.text = String(newText.prefix(characterLimit))
                                }
                            }
                            .focused($focusedItemID, equals: option.id)
                    }
                    .onMove(perform: { from, to in
                        pollOptions.move(fromOffsets: from, toOffset: to)
                    })
                } header: {
                    Text(
                        OWSLocalizedString(
                            "POLL_OPTIONS_LABEL",
                            comment: "Header for the poll options text boxes when making a new poll"
                        )
                    )
                    .font(.headline)
                    .foregroundColor(Color.Signal.label)
                }
                .onChange(of: pollOptions) { _ in
                    onChange()
                }
                SignalSection {
                    Toggle(
                        OWSLocalizedString(
                            "POLL_ALLOW_MULTIPLE_LABEL",
                            comment: "Title for a toggle allowing multiple votes for a poll."
                        ),
                        isOn: Binding(
                            get: { allowMultipleVotes },
                            set: { allowMultipleVotes = $0 }
                        )
                    )
                }
            }
        }
        .navigationTitle(OWSLocalizedString(
            "POLL_CREATE_TITLE",
            comment: "Title of create poll pane"
        ))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if #available(iOS 26.0, *) {
                    Button(action: {
                        viewModel.onDismiss()
                    }) {
                        Image(Theme.iconName(.xBold))
                    }
                    .accessibilityLabel(CommonStrings.cancelButton)
                } else {
                    Button(CommonStrings.cancelButton, action: {
                        viewModel.onDismiss()
                    })
                    .foregroundColor(Color.Signal.label)
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                let filteredPollOptions = pollOptions.filter({ !$0.text.stripped.isEmpty })
                let sendButtonEnabled = filteredPollOptions.count >= 2 && !pollQuestion.isEmpty

                if #available(iOS 26.0, *) {
                    Button(action: {
                        sendButtonPressed(sendButtonEnabled: sendButtonEnabled)
                    }) {
                        Image(Theme.iconName(.arrowUp))
                    }
                    .accessibilityLabel(MessageStrings.sendButton)
                    .tint(Color.Signal.ultramarine)
#if compiler(>=6.2)
                    .buttonStyle(.glassProminent)
#endif
                    .opacity(sendButtonEnabled ? 1 : 0.5)
                } else {
                    Button(MessageStrings.sendButton, action: {
                        sendButtonPressed(sendButtonEnabled: sendButtonEnabled)
                    })
                    .foregroundColor(Color.Signal.label)
                    .opacity(sendButtonEnabled ? 1 : 0.5)
                }
            }
        }
    }

    private func sendButtonPressed(sendButtonEnabled: Bool) {
        if sendButtonEnabled {
            viewModel.onSend(
                pollOptions: pollOptions.map(\.text).filter { !$0.isEmpty },
                question: pollQuestion,
                allowMultipleVotes: allowMultipleVotes
            )
        } else {
            viewModel.showToast(hasQuestion: !pollQuestion.isEmpty, hasEnoughOptions: pollOptions.count >= 3)
        }
    }

    private func indexForOption(option: NewOption) -> Int {
        return pollOptions.firstIndex(of: option)!
    }

    private func onChange() {
        // Filter out all blank fields since user may have deleted a middle option.
        var filteredPollOptions = pollOptions.filter({ !$0.text.isEmpty })

        if filteredPollOptions.count >= 10 {
            return
        }

        // If 0/1 option, we want exactly 2 fields in this case, so don't append or filter.
        if filteredPollOptions.count <= 1 && pollOptions.count == 2 {
            return
        }

        // To avoid infinite recursion caused by editing the pollOptions array,
        // check if we're setup correctly (blank row at the end, none in the middle)
        // and return early if so.
        if pollOptions.last!.text.isEmpty && filteredPollOptions.count == pollOptions.count - 1 {
            return
        }

        // Add back a blank field at the end since we aren't at the option limit.
        // Note this will call onChange() again since we are changing the pollOptions array.
        filteredPollOptions.append(NewOption(text: ""))
        let oldPollRowCount = pollOptions.count
        pollOptions = filteredPollOptions

        // Re-focus latest row if this is a deletion so we don't lose
        // first responder status.
        if filteredPollOptions.count < oldPollRowCount {
            focusedItemID = pollOptions.last?.id
        }
    }
}

#Preview {
    NewPollView(viewModel: NewPollViewModel())
}
