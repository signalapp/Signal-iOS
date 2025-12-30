//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI
import SwiftUI

public protocol PollSendDelegate: AnyObject {
    func sendPoll(question: String, options: [String], allowMultipleVotes: Bool)
}

class NewPollViewController: HostingController<NewPollView> {
    weak var sendDelegate: PollSendDelegate?
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
        allowMultipleVotes: Bool,
    ) {
        sendDelegate?.sendPoll(
            question: question,
            options: pollOptions,
            allowMultipleVotes: allowMultipleVotes,
        )

        dismiss(animated: true)
    }

    fileprivate func showToast(
        hasQuestion: Bool,
        hasEnoughOptions: Bool,
    ) {
        var toast: ToastController
        if !hasQuestion, !hasEnoughOptions {
            toast = ToastController(text: OWSLocalizedString(
                "POLL_CREATE_ERROR_TOAST_NO_QUESTION_OR_ENOUGH_OPTIONS",
                comment: "Toast telling user to add options and question to poll.",
            ))
        } else if !hasQuestion {
            toast = ToastController(text: OWSLocalizedString(
                "POLL_CREATE_ERROR_TOAST_NO_QUESTION",
                comment: "Toast telling user to add a question to poll.",
            ))
        } else {
            toast = ToastController(text: OWSLocalizedString(
                "POLL_CREATE_ERROR_TOAST_NOT_ENOUGH_OPTIONS",
                comment: "Toast telling user to add more options to poll.",
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
            allowMultipleVotes: Bool,
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
        allowMultipleVotes: Bool,
    ) {
        actionsDelegate?.onSend(
            pollOptions: pollOptions,
            question: question,
            allowMultipleVotes: allowMultipleVotes,
        )
    }

    func showToast(
        hasQuestion: Bool,
        hasEnoughOptions: Bool,
    ) {
        actionsDelegate?.showToast(
            hasQuestion: hasQuestion,
            hasEnoughOptions: hasEnoughOptions,
        )
    }
}

struct NewPollView: View {
    private enum LayoutMetrics {
        static let minTextViewHeight: CGFloat = 35
        static let maxTextViewHeight: CGFloat = 142
        static let oneLineHeight: CGFloat = 40
    }

    struct NewOption: Identifiable, Equatable {
        let id = UUID()
        var text: String
    }

    fileprivate let viewModel: NewPollViewModel
    @State var pollQuestion: String = ""
    @State var pollOptions: [NewOption] = [NewOption(text: ""), NewOption(text: "")]
    @State var allowMultipleVotes: Bool = false

    @FocusState private var focusedItemID: UUID?
    @FocusState private var focusQuestionField: Bool

    fileprivate init(viewModel: NewPollViewModel) {
        self.viewModel = viewModel
    }

    struct PollResizingTextEditor: View {
        @Binding var text: String
        @State private var editorWidth: CGFloat = 0
        var placeholder: String

        // Submit
        var onSubmit: () -> Void

        // Focus
        var questionFieldFocus: FocusState<Bool>.Binding?
        var optionFieldFocus: FocusState<UUID?>.Binding?
        var optionFieldId: UUID?

        static let characterLimit: Int = 100

        var body: some View {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundColor(Color.Signal.secondaryLabel)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                        .accessibilityHidden(true)
                }
                textEditor()
            }
            .frame(height: NewPollView.calculateHeight(text: text, textViewWidth: editorWidth))
        }

        @ViewBuilder
        private func textEditor() -> some View {
            let editor = TextEditor(text: $text)
                .onChange(of: text) { newText in
                    // remove newlines but detect them and subsitute with onSubmit.
                    text = text.components(separatedBy: CharacterSet.newlines).joined()
                    if let last = newText.last, last.isNewline {
                        onSubmit()
                        return
                    }
                    if newText.count > PollResizingTextEditor.characterLimit {
                        let resizedText = String(newText.prefix(PollResizingTextEditor.characterLimit))
                        if text != resizedText {
                            text = resizedText
                        }
                    }
                    if text.stripped.isEmpty {
                        text = ""
                    }
                }
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear {
                                editorWidth = geo.size.width
                            }
                            .onChange(of: geo.size.width) { newWidth in
                                editorWidth = newWidth
                            }
                    },
                )
                .accessibilityLabel(placeholder)

            if let questionFieldFocus {
                editor.focused(questionFieldFocus)
            } else if let optionFieldFocus, let optionFieldId {
                editor.focused(optionFieldFocus, equals: optionFieldId)
            } else {
                editor
            }
        }
    }

    struct OptionRow: View {
        @Binding var option: NewOption
        let optionIndex: Int
        let totalCount: Int
        var focusedField: FocusState<UUID?>.Binding
        var onSubmit: () -> Void

        var body: some View {
            let remainingChars = PollResizingTextEditor.characterLimit - option.text.count
            let displayRemainingChars = remainingChars <= 20 ? NewPollView.localizedNumber(from: remainingChars) : ""
            let countdownColor = remainingChars <= 5 ? Color.Signal.red : Color.Signal.tertiaryLabel
            let shouldHaveEmptyPlaceholder = totalCount > 2 && optionIndex != totalCount - 1
            let placeholder = shouldHaveEmptyPlaceholder ? "" : localizedOptionPlaceholderText(index: optionIndex + 1)

            HStack {
                PollResizingTextEditor(
                    text: $option.text,
                    placeholder: placeholder,
                    onSubmit: onSubmit,
                    optionFieldFocus: focusedField,
                    optionFieldId: option.id,
                )

                if !option.text.isEmpty, totalCount > 2 {
                    Spacer()
                    Image("poll-drag")
                }
            }
            .overlay(
                Text("\(displayRemainingChars)")
                    .font(.system(size: 15))
                    .foregroundColor(countdownColor),
                alignment: .bottomTrailing,
            )
        }

        private func localizedOptionPlaceholderText(index: Int) -> String {
            let locText = OWSLocalizedString(
                "POLL_OPTION_PLACEHOLDER_PREFIX",
                comment: "Placeholder text for an option row when creating a poll. This will have a number appended to it (Option 1, Option 2)",
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
                    let remainingChars = PollResizingTextEditor.characterLimit - pollQuestion.count
                    let displayRemainingChars = remainingChars <= 20 ? NewPollView.localizedNumber(from: remainingChars) : ""
                    let countdownColor = remainingChars <= 5 ? Color.Signal.red : Color.Signal.tertiaryLabel

                    PollResizingTextEditor(
                        text: $pollQuestion,
                        placeholder: OWSLocalizedString(
                            "POLL_QUESTION_PLACEHOLDER_TEXT",
                            comment: "Placeholder text for poll question",
                        ),
                        onSubmit: {
                            if let nextBlankRow = findFirstBlankRow() {
                                focusedItemID = nextBlankRow.id
                            }
                        },
                        questionFieldFocus: $focusQuestionField,
                    )
                    .overlay(
                        Text("\(displayRemainingChars)")
                            .font(.system(size: 15))
                            .foregroundColor(countdownColor),
                        alignment: .bottomTrailing,
                    )
                    .onAppear {
                        focusQuestionField = true
                    }
                } header: {
                    Text(
                        OWSLocalizedString(
                            "POLL_QUESTION_LABEL",
                            comment: "Header for the poll question text box when making a new poll",
                        ),
                    )
                    .font(.headline)
                    .foregroundColor(Color.Signal.label)
                }
                SignalSection {
                    ForEach($pollOptions) { $option in
                        let index = indexForOption(option: option)
                        OptionRow(
                            option: $option,
                            optionIndex: index,
                            totalCount: pollOptions.count,
                            focusedField: $focusedItemID,
                            onSubmit: {
                                if let nextBlankRow = findFirstBlankRow() {
                                    focusedItemID = nextBlankRow.id
                                }
                            },
                        )
                    }
                    .onMove(perform: { from, to in
                        pollOptions.move(fromOffsets: from, toOffset: to)
                    })
                } header: {
                    Text(
                        OWSLocalizedString(
                            "POLL_OPTIONS_LABEL",
                            comment: "Header for the poll options text boxes when making a new poll",
                        ),
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
                            comment: "Title for a toggle allowing multiple votes for a poll.",
                        ),
                        isOn: Binding(
                            get: { allowMultipleVotes },
                            set: { allowMultipleVotes = $0 },
                        ),
                    )
                }
            }
        }
        .navigationTitle(OWSLocalizedString(
            "POLL_CREATE_TITLE",
            comment: "Title of create poll pane",
        ))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if #available(iOS 26.0, *) {
                    Button(action: {
                        viewModel.onDismiss()
                    }) {
                        Image(Theme.iconName(.x26))
                    }
                    .accessibilityLabel(CommonStrings.cancelButton)
                    .foregroundColor(Color.Signal.label)
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
                        Image(Theme.iconName(.arrowUp30))
                            .foregroundColor(.white)
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

    fileprivate static func calculateHeight(text: String, textViewWidth: CGFloat) -> CGFloat {
        let heightPadding = 16.0
        let characterCountBuffer = 15.0
        let maxSize = CGSize(
            width: textViewWidth - characterCountBuffer,
            height: CGFloat.greatestFiniteMagnitude,
        )
        var textToMeasure: NSAttributedString = NSAttributedString(string: text, attributes: [.font: UIFont.dynamicTypeBody])

        if textToMeasure.isEmpty {
            textToMeasure = NSAttributedString(string: "M", attributes: [.font: UIFont.dynamicTypeBody])
        }
        var contentSize = textToMeasure.boundingRect(with: maxSize, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).size
        contentSize.height += heightPadding

        let newHeight = CGFloat.clamp(
            contentSize.height.rounded(),
            min: LayoutMetrics.minTextViewHeight,
            max: LayoutMetrics.maxTextViewHeight,
        )

        // Measured height for one line is taller than the average one-line TextField and looks strange.
        // Reduce to minTextViewHeight in this case.
        return newHeight <= LayoutMetrics.oneLineHeight ? LayoutMetrics.minTextViewHeight : newHeight
    }

    static func localizedNumber(from number: Int) -> String {
        let formatter: NumberFormatter = {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            return f
        }()

        return formatter.string(from: NSNumber(value: number))!
    }

    private func findFirstBlankRow() -> NewOption? {
        for option in pollOptions {
            if option.text.isEmpty {
                return option
            }
        }
        return nil
    }

    private func sendButtonPressed(sendButtonEnabled: Bool) {
        if sendButtonEnabled {
            viewModel.onSend(
                pollOptions: pollOptions.map(\.text)
                    .filter { !$0.stripped.isEmpty }
                    .map { $0.stripped },
                question: pollQuestion.stripped,
                allowMultipleVotes: allowMultipleVotes,
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
        let filteredPollOptions = pollOptions.filter({ !$0.text.stripped.isEmpty })

        if filteredPollOptions.count >= 10 {
            return
        }

        // If 0/1 option, we want exactly 2 fields in this case, so don't append or filter.
        if filteredPollOptions.count <= 1, pollOptions.count == 2 {
            return
        }

        // To avoid infinite recursion caused by editing the pollOptions array,
        // check if we're setup correctly (blank row at the end, none in the middle)
        // and return early if so.
        if pollOptions.last!.text.isEmpty, filteredPollOptions.count == pollOptions.count - 1 {
            return
        }

        // Add back a blank field at the end since we aren't at the option limit.
        // Note this will call onChange() again since we are changing the pollOptions array.
        let oldPollRowCount = pollOptions.count
        withAnimation {
            pollOptions = filteredPollOptions
            pollOptions.append(NewOption(text: ""))
        }

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
