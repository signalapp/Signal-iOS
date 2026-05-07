//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

public protocol PollSendDelegate: AnyObject {
    func sendPoll(question: String, options: [String], allowMultipleVotes: Bool)
}

// MARK: -

class NewPollViewController2: OWSViewController, UITableViewDelegate, OWSNavigationChildController {

    private enum Section: Int, CaseIterable {
        case question
        case options
        case allowMultipleVotes
    }

    /// - Important
    /// Two `OptionRow` instances with the same text but different IDs are
    /// unique as far as `UITableViewDiffableDataSource` is concerned.
    private struct OptionRow: Identifiable, Equatable, Hashable {
        let id = UUID()
        var text: String

        var isBlank: Bool { text.strippedOrNil == nil }

        static func makeBlank() -> OptionRow { OptionRow(text: "") }
    }

    private enum SendabilityState {
        case missingQuestionAndOptions
        case missingQuestion
        case missingOptions
        case sendable
    }

    private let questionItemID = UUID()
    private let multipleVotesItemID = UUID()
    private var questionText = ""
    private var optionRows: [OptionRow] = [.makeBlank(), .makeBlank()]
    private var allowMultipleVotes = true
    private var sendabilityState: SendabilityState = .missingQuestionAndOptions

    weak var sendDelegate: PollSendDelegate?

    // MARK: - OWSNavigationChildController

    var navbarBackgroundColorOverride: UIColor? {
        .Signal.groupedBackground
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        let cancelBarButtonItem: UIBarButtonItem
        if #available(iOS 26, *) {
            cancelBarButtonItem = .systemItem(
                .close,
                action: { [weak self] in
                    self?.dismiss(animated: true)
                },
            )
        } else {
            cancelBarButtonItem = .button(
                title: CommonStrings.cancelButton,
                style: .plain,
                action: { [weak self] in
                    self?.dismiss(animated: true)
                },
            )
            cancelBarButtonItem.setTitleTextAttributes(
                [.foregroundColor: UIColor.Signal.label],
                for: .normal,
            )
        }
        navigationItem.leftBarButtonItem = cancelBarButtonItem

        title = OWSLocalizedString(
            "POLL_CREATE_TITLE",
            comment: "Title of create poll pane",
        )

        let sendBarButtonItem: UIBarButtonItem
        if #available(iOS 26, *) {
            sendBarButtonItem = .button(
                image: .arrowUp30,
                style: .prominent,
                action: { [weak self] in
                    self?.didTapSendButton()
                },
            )
            sendBarButtonItem.accessibilityLabel = MessageStrings.sendButton
        } else {
            sendBarButtonItem = .button(
                title: MessageStrings.sendButton,
                style: .done,
                action: { [weak self] in
                    self?.didTapSendButton()
                },
            )
        }
        navigationItem.rightBarButtonItem = sendBarButtonItem

        view.backgroundColor = .Signal.groupedBackground
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])

        tableView.isEditing = true
        updateSendabilityState()

        var snapshot = NSDiffableDataSourceSnapshot<Section, UUID>()
        snapshot.appendSections(Section.allCases)
        snapshot.appendItems([questionItemID], toSection: .question)
        snapshot.appendItems(optionRows.map(\.id), toSection: .options)
        snapshot.appendItems([multipleVotesItemID], toSection: .allowMultipleVotes)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if
            let questionRowCell = tableView.cellForRow(at: IndexPath(
                row: 0,
                section: Section.question.rawValue,
            )) as? TextViewTableViewCell
        {
            questionRowCell.textView.becomeFirstResponder()
        }
    }

    // MARK: - Views

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.register(TextViewTableViewCell.self, forCellReuseIdentifier: TextViewTableViewCell.reuseIdentifier)
        tableView.register(ToggleTableViewCell.self, forCellReuseIdentifier: ToggleTableViewCell.reuseIdentifier)
        return tableView
    }()

    private lazy var dataSource: OWSTableViewDiffableDataSource<Section, UUID> = {
        let dataSource = OWSTableViewDiffableDataSource<Section, UUID>(
            tableView: tableView,
        ) { [weak self] tableView, indexPath, itemIdentifier in
            guard let self, let section = Section(rawValue: indexPath.section) else {
                return UITableViewCell()
            }
            switch section {
            case .question:
                return self.dequeueQuestionCell(for: tableView, indexPath: indexPath)
            case .options:
                return self.dequeueOptionCell(for: tableView, indexPath: indexPath, itemIdentifier: itemIdentifier)
            case .allowMultipleVotes:
                return self.dequeueMultipleVotesCell(for: tableView, indexPath: indexPath)
            }
        }

        dataSource.canMoveRow = { [weak self] indexPath in
            guard let self else { return false }

            switch Section(rawValue: indexPath.section) {
            case nil, .question, .allowMultipleVotes:
                return false
            case .options:
                guard let optionRow = optionRows[safe: indexPath.row] else {
                    return false
                }
                return !optionRow.isBlank
            }
        }

        dataSource.didMoveRow = { [weak self, weak dataSource] sourceIndexPath, destinationIndexPath in
            guard let self, let dataSource else { return }

            let movedRow = optionRows.remove(at: sourceIndexPath.row)
            optionRows.insert(movedRow, at: destinationIndexPath.row)
            applyOptionRowsToSnapshot(optionRowIDsToReconfigure: [])
        }

        // Mitigates a visual artifact: when deleting a "middle" row, the square
        // corners of that middle row are visible while it's being deleted,
        // which looks janky with the `.automatic` animation.
        dataSource.defaultRowAnimation = .fade

        return dataSource
    }()

    // MARK: - Question cell

    private func dequeueQuestionCell(
        for tableView: UITableView,
        indexPath: IndexPath,
    ) -> UITableViewCell {
        guard
            let cell = tableView.dequeueReusableCell(
                withIdentifier: TextViewTableViewCell.reuseIdentifier,
                for: indexPath,
            ) as? TextViewTableViewCell
        else {
            return UITableViewCell()
        }

        cell.configure(
            text: questionText,
            placeholder: OWSLocalizedString(
                "POLL_QUESTION_PLACEHOLDER_TEXT",
                comment: "Placeholder text for poll question",
            ),
            onDidBeginEditing: {},
            onTextDidChange: { [weak self] newText in
                guard let self else { return }

                questionText = newText ?? ""
                updateSendabilityState()

                // Reconfigure the question row, so it resizes if necessary for the
                // new text.
                var snapshot = dataSource.snapshot()
                snapshot.reconfigureItems([questionItemID])
                dataSource.apply(snapshot, animatingDifferences: true)
            },
            onReturnKeyPressed: { [weak self] in
                guard let self else { return }
                let firstOptionIndexPath = IndexPath(row: 0, section: Section.options.rawValue)
                if let nextCell = self.tableView.cellForRow(at: firstOptionIndexPath) as? TextViewTableViewCell {
                    nextCell.textView.becomeFirstResponder()
                }
            },
        )

        return cell
    }

    // MARK: - Option cell

    private func dequeueOptionCell(
        for tableView: UITableView,
        indexPath: IndexPath,
        itemIdentifier: UUID,
    ) -> UITableViewCell {
        guard
            let cell = tableView.dequeueReusableCell(
                withIdentifier: TextViewTableViewCell.reuseIdentifier,
                for: indexPath,
            ) as? TextViewTableViewCell,
            let rowIndex = optionRows.firstIndex(where: { $0.id == itemIdentifier })
        else {
            return UITableViewCell()
        }

        cell.configure(
            text: optionRows[rowIndex].text,
            placeholder: String.nonPluralLocalizedStringWithFormat(
                OWSLocalizedString(
                    "POLL_OPTION_PLACEHOLDER_FORMAT",
                    comment: #"Format text for the placeholder of an option row when creating a poll. Embeds {{ the number of this option in a list, as a pre-localized string }}, so it should look like "Option 1", "Option 2"."#,
                ),
                TextViewTableViewCell.localizedNumber(rowIndex + 1),
            ),
            onDidBeginEditing: { [weak self, weak tableView] in
                guard let self, let tableView else { return }

                removeNonTrailingBlankOptionRows()

                if rowIndex == optionRows.count - 1 {
                    tableView.scrollToRow(
                        at: IndexPath(row: 0, section: Section.allowMultipleVotes.rawValue),
                        at: .bottom,
                        animated: true,
                    )
                }
            },
            onTextDidChange: { [weak self] newText in
                guard let self else { return }

                updateOptionRowText(newText ?? "", rowIndex: rowIndex)
                updateSendabilityState()
            },
            onReturnKeyPressed: { [weak self] in
                guard let self else { return }
                let nextOptionIndexPath = IndexPath(row: rowIndex + 1, section: Section.options.rawValue)
                if let nextCell = self.tableView.cellForRow(at: nextOptionIndexPath) as? TextViewTableViewCell {
                    nextCell.textView.becomeFirstResponder()
                }
            },
        )

        return cell
    }

    // MARK: - Multiple votes cell

    private func dequeueMultipleVotesCell(
        for tableView: UITableView,
        indexPath: IndexPath,
    ) -> UITableViewCell {
        guard
            let cell = tableView.dequeueReusableCell(
                withIdentifier: ToggleTableViewCell.reuseIdentifier,
                for: indexPath,
            ) as? ToggleTableViewCell
        else {
            return UITableViewCell()
        }

        cell.configure(
            title: OWSLocalizedString(
                "POLL_ALLOW_MULTIPLE_LABEL",
                comment: "Title for a toggle allowing multiple votes for a poll.",
            ),
            isOn: allowMultipleVotes,
        )

        cell.onToggleDidChange = { [weak self] isOn in
            guard let self else { return }
            self.allowMultipleVotes = isOn
        }

        return cell
    }

    // MARK: - Option row invariants

    private func removeNonTrailingBlankOptionRows() {
        if optionRows.count <= 2 {
            return
        }

        var newOptionRows = optionRows.filter { !$0.isBlank }

        if let lastOptionRow = optionRows.last, lastOptionRow.isBlank {
            // Preserve the trailing blank row if it exists.
            newOptionRows.append(lastOptionRow)
        } else if newOptionRows.count < 10 {
            // If not, and we have room, add a new blank row.
            newOptionRows.append(.makeBlank())
        }

        optionRows = newOptionRows
        applyOptionRowsToSnapshot(optionRowIDsToReconfigure: [])
    }

    private func updateOptionRowText(
        _ newText: String,
        rowIndex: Int,
    ) {
        optionRows[rowIndex].text = newText
        let optionRowID = optionRows[rowIndex].id

        if optionRows.count == 2, optionRows.contains(where: \.isBlank) {
            applyOptionRowsToSnapshot(optionRowIDsToReconfigure: [optionRowID])
            return
        }

        if let lastOptionRow = optionRows.last, lastOptionRow.isBlank {
            applyOptionRowsToSnapshot(optionRowIDsToReconfigure: [optionRowID])
            return
        }

        if optionRows.count >= 10 {
            applyOptionRowsToSnapshot(optionRowIDsToReconfigure: [optionRowID])
            return
        }

        optionRows.append(.makeBlank())
        applyOptionRowsToSnapshot(optionRowIDsToReconfigure: [])
    }

    /// Apply the current `optionRows` state to the snapshot.
    ///
    /// If `optionRowIDsToReconfigure` is empty, all option rows will be
    /// reconfigured. This is useful to ensure the corresponding cells are
    /// capturing the correct row indexes.
    ///
    /// If `optionRowIDsToReconfigure` is non-empty, only the cells for the
    /// given IDs will be reconfigured. This is useful to resize cells that may
    /// have changed, when the caller knows no row indexes have changed.
    private func applyOptionRowsToSnapshot(
        optionRowIDsToReconfigure: [OptionRow.ID],
    ) {
        let optionRowIDs = optionRows.map(\.id)

        var snapshot = dataSource.snapshot()
        snapshot.deleteItems(snapshot.itemIdentifiers(inSection: .options))
        snapshot.appendItems(optionRowIDs, toSection: .options)

        if optionRowIDsToReconfigure.isEmpty {
            snapshot.reconfigureItems(optionRowIDs)
        } else {
            snapshot.reconfigureItems(optionRowIDsToReconfigure)
        }

        dataSource.apply(
            snapshot,
            animatingDifferences: true,
        )
    }

    // MARK: - Sendability

    private func updateSendabilityState() {
        let missingQuestion = questionText.strippedOrNil == nil
        let missingOptions = optionRows.count { !$0.isBlank } < 2
        let shouldFadeSendButton: Bool

        if missingQuestion, missingOptions {
            sendabilityState = .missingQuestionAndOptions
            shouldFadeSendButton = true
        } else if missingQuestion {
            sendabilityState = .missingQuestion
            shouldFadeSendButton = true
        } else if missingOptions {
            sendabilityState = .missingOptions
            shouldFadeSendButton = true
        } else {
            sendabilityState = .sendable
            shouldFadeSendButton = false
        }

        let sendBarButtonItem = navigationItem.rightBarButtonItem!
        if
            #available(iOS 26, *),
            shouldFadeSendButton
        {
            sendBarButtonItem.tintColor = .Signal.ultramarine.withAlphaComponent(0.5)
        } else if #available(iOS 26, *) {
            sendBarButtonItem.tintColor = .Signal.ultramarine
        } else if shouldFadeSendButton {
            sendBarButtonItem.setTitleTextAttributes(
                [.foregroundColor: UIColor.Signal.label.withAlphaComponent(0.5)],
                for: .normal,
            )
        } else {
            sendBarButtonItem.setTitleTextAttributes(
                [.foregroundColor: UIColor.Signal.label],
                for: .normal,
            )
        }
    }

    private func didTapSendButton() {
        let toastText: String
        switch sendabilityState {
        case .missingQuestionAndOptions:
            toastText = OWSLocalizedString(
                "POLL_CREATE_ERROR_TOAST_NO_QUESTION_OR_ENOUGH_OPTIONS",
                comment: "Toast telling user to add options and question to poll.",
            )
        case .missingQuestion:
            toastText = OWSLocalizedString(
                "POLL_CREATE_ERROR_TOAST_NO_QUESTION",
                comment: "Toast telling user to add a question to poll.",
            )
        case .missingOptions:
            toastText = OWSLocalizedString(
                "POLL_CREATE_ERROR_TOAST_NOT_ENOUGH_OPTIONS",
                comment: "Toast telling user to add more options to poll.",
            )
        case .sendable:
            sendDelegate?.sendPoll(
                question: questionText.stripped,
                options: optionRows.filter { !$0.isBlank }.map { $0.text.stripped },
                allowMultipleVotes: allowMultipleVotes,
            )
            dismiss(animated: true)
            return
        }

        presentToast(text: toastText)
    }

    // MARK: - UITableViewDelegate

    func tableView(
        _ tableView: UITableView,
        viewForHeaderInSection section: Int,
    ) -> UIView? {
        let title: String
        switch Section(rawValue: section) {
        case .question:
            title = OWSLocalizedString(
                "POLL_QUESTION_LABEL",
                comment: "Header for the poll question text box when making a new poll",
            )
        case .options:
            title = OWSLocalizedString(
                "POLL_OPTIONS_LABEL",
                comment: "Header for the poll options text boxes when making a new poll",
            )
        case nil, .allowMultipleVotes:
            return nil
        }

        let label = UILabel()
        label.text = title
        label.font = .dynamicTypeHeadlineClamped
        label.textColor = .Signal.label
        label.numberOfLines = 0

        let container = UIView()
        container.addSubview(label)
        label.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(hMargin: 12, vMargin: 12))
        return container
    }

    func tableView(
        _ tableView: UITableView,
        editingStyleForRowAt indexPath: IndexPath,
    ) -> UITableViewCell.EditingStyle {
        .none
    }

    func tableView(
        _ tableView: UITableView,
        shouldIndentWhileEditingRowAt indexPath: IndexPath,
    ) -> Bool {
        false
    }

    func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath,
    ) -> IndexPath {
        guard
            sourceIndexPath.section == Section.options.rawValue,
            proposedDestinationIndexPath.section == Section.options.rawValue
        else {
            return sourceIndexPath
        }

        let lastOptionRowIndex = optionRows.count - 1
        if
            proposedDestinationIndexPath.row == lastOptionRowIndex,
            optionRows[lastOptionRowIndex].isBlank
        {
            // Disallow moving a row to follow a blank trailing row.
            return sourceIndexPath
        }

        return proposedDestinationIndexPath
    }
}

// MARK: - TextViewTableViewCell

private class TextViewTableViewCell: UITableViewCell, TextViewWithPlaceholderDelegate {

    static let reuseIdentifier = "TextViewTableViewCell"

    let textView = TextViewWithPlaceholder()
    var onDidBeginEditing: (() -> Void)?
    var onTextDidChange: ((_ newText: String?) -> Void)?
    var onReturnKeyPressed: (() -> Void)?

    private let remainingCharactersLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15)
        label.isHidden = true
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none
        textView.editorFont = .dynamicTypeBodyClamped
        textView.delegate = self
        contentView.preservesSuperviewLayoutMargins = false
        contentView.layoutMargins = UIEdgeInsets(hMargin: 16, vMargin: 7)
        contentView.addSubview(textView)
        textView.autoPinEdgesToSuperviewMargins()

        // Not a subview of contentView, because we want this sitting under the
        // "grabber handle" shown when we're in edit mode.
        addSubview(remainingCharactersLabel)
        remainingCharactersLabel.autoPinEdge(.trailing, to: .trailing, of: self, withOffset: -12)
        remainingCharactersLabel.autoPinEdge(.bottom, to: .bottom, of: self, withOffset: -12)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - TextViewWithPlaceholderDelegate

    static let maxAllowedCharacters = 100

    func textViewDidUpdateText(_ textView: TextViewWithPlaceholder) {
        if var text = textView.text {
            // Space-separate any newline-separated substrings
            text = text
                .components(separatedBy: .newlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            if text.count > Self.maxAllowedCharacters {
                text = String(text.prefix(Self.maxAllowedCharacters))
            }

            if text != textView.text {
                textView.text = text
            }
        }

        updateRemainingCharactersLabel()
        onTextDidChange?(textView.text)
    }

    private func updateRemainingCharactersLabel() {
        let remaining = Self.maxAllowedCharacters - (textView.text ?? "").count
        if remaining <= 20 {
            remainingCharactersLabel.isHidden = false
            remainingCharactersLabel.text = Self.localizedNumber(remaining)
            remainingCharactersLabel.textColor = remaining < 5 ? .Signal.red : .Signal.tertiaryLabel
        } else {
            remainingCharactersLabel.isHidden = true
        }
    }

    func textView(
        _ textView: TextViewWithPlaceholder,
        uiTextView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String,
    ) -> Bool {
        if
            let lastChar = text.last,
            lastChar.isNewline || lastChar == "\t"
        {
            onReturnKeyPressed?()
        }

        return true
    }

    func textViewDidBeginEditing(_ textView: TextViewWithPlaceholder) {
        onDidBeginEditing?()
    }

    func textViewDidEndEditing(_ textView: TextViewWithPlaceholder) {
        if
            let strippedText = textView.text?.stripped,
            strippedText != textView.text
        {
            textView.text = strippedText
        }
    }

    // MARK: -

    func configure(
        text: String,
        placeholder: String,
        onDidBeginEditing: @escaping () -> Void,
        onTextDidChange: @escaping (_ newText: String?) -> Void,
        onReturnKeyPressed: @escaping () -> Void,
    ) {
        self.onDidBeginEditing = nil
        self.onTextDidChange = nil
        self.onReturnKeyPressed = nil

        // Avoid setting this unless necessary, or we'll be called back via the
        // TextViewWithPlaceholderDelegate. We may just have a new index.
        if textView.text != text {
            textView.text = text
        }

        textView.placeholderText = placeholder

        self.onDidBeginEditing = onDidBeginEditing
        self.onTextDidChange = onTextDidChange
        self.onReturnKeyPressed = onReturnKeyPressed
    }

    // MARK: -

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    static func localizedNumber(_ value: Int) -> String {
        numberFormatter.string(from: NSNumber(value: value))!
    }
}

// MARK: - ToggleTableViewCell

private class ToggleTableViewCell: UITableViewCell {

    static let reuseIdentifier = "ToggleTableViewCell"

    var onToggleDidChange: ((_ isOn: Bool) -> Void)?

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeBodyClamped
        label.numberOfLines = 0
        return label
    }()

    private let toggle = UISwitch()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none
        toggle.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                self.onToggleDidChange?(self.toggle.isOn)
            },
            for: .valueChanged,
        )
        accessoryView = toggle
        editingAccessoryView = toggle

        contentView.addSubview(titleLabel)
        titleLabel.autoPinEdgesToSuperviewMargins()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, isOn: Bool) {
        titleLabel.text = title
        toggle.isOn = isOn
    }
}

// MARK: - Previews

#if DEBUG

private class PreviewPollViewController: UINavigationController, PollSendDelegate {
    func sendPoll(question: String, options: [String], allowMultipleVotes: Bool) {
        print("\(question)? \(options), allowMultipleVotes: \(allowMultipleVotes)")
    }

    init() {
        let pollViewController = NewPollViewController2()
        super.init(rootViewController: pollViewController)
        pollViewController.sendDelegate = self
    }

    required init?(coder aDecoder: NSCoder) {
        owsFail("Not implemented!")
    }
}

@available(iOS 17, *)
#Preview {
    PreviewPollViewController()
}

#endif
