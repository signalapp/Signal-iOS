//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import SignalServiceKit

class ContactNoteSheet: OWSTableSheetViewController {
    struct Context {
        let db: any DB
        let recipientDatabaseTable: any RecipientDatabaseTable
        let nicknameManager: any NicknameManager
    }

    private let contactNoteTableViewController: ContactNoteTableViewController
    override var tableViewController: OWSTableViewController2 {
        get { contactNoteTableViewController }
        set { }
    }

    private let thread: TSContactThread
    private let context: Context

    private weak var fromViewController: UIViewController?

    func present(from viewController: UIViewController) {
        fromViewController = viewController
        viewController.present(self, animated: true)
    }

    init(thread: TSContactThread, context: Context) {
        self.thread = thread
        self.context = context
        self.contactNoteTableViewController = ContactNoteTableViewController(thread: thread, context: context)
        super.init()
        self.contactNoteTableViewController.didTapEdit = { [weak self] in
            self?.didTapEdit()
        }
    }

    override func updateTableContents(shouldReload: Bool = true) {
        self.contactNoteTableViewController.updateTableContents(shouldReload: shouldReload)
        self.updateMinimizedHeight()
    }

    private func didTapEdit() {
        let nicknameEditor: NicknameEditorViewController? = self.context.db.read { tx in
            NicknameEditorViewController.create(
                for: self.thread.contactAddress,
                context: .init(
                    db: self.context.db,
                    nicknameManager: self.context.nicknameManager
                ),
                tx: tx
            )
        }
        guard let nicknameEditor else { return }
        let navigationController = OWSNavigationController(rootViewController: nicknameEditor)

        self.dismiss(animated: true) { [weak fromViewController = self.fromViewController] in
            fromViewController?.presentFormSheet(navigationController, animated: true)
        }
    }
}

private class ContactNoteTableViewController: OWSTableViewController2, TextViewWithPlaceholderDelegate {
    typealias Context = ContactNoteSheet.Context

    private let thread: TSContactThread
    private let context: Context
    var didTapEdit: (() -> Void)?

    private let noteTextView: TextViewWithPlaceholder = {
        let textView = TextViewWithPlaceholder()
        textView.isEditable = false
        textView.linkTextAttributes = [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        return textView
    }()

    init(thread: TSContactThread, context: Context) {
        self.thread = thread
        self.context = context
    }

    func updateTableContents(shouldReload: Bool) {
        let header: UIView = {
            let headerContainer = UIView()
            headerContainer.layoutMargins = .init(
                top: 0,
                left: 16,
                bottom: 24,
                right: 16
            )

            let titleLabel = UILabel()
            headerContainer.addSubview(titleLabel)
            titleLabel.text = OWSLocalizedString(
                "CONTACT_NOTE_TITLE",
                comment: "Title for a view showing the note that has been set for a profile."
            )
            titleLabel.font = .dynamicTypeHeadline.semibold()
            titleLabel.textColor = Theme.primaryTextColor
            titleLabel.autoCenterInSuperviewMargins()
            titleLabel.autoPinHeightToSuperviewMargins()

            let editButton = OWSButton(
                title: CommonStrings.editButton,
                block: { [weak self] in
                    self?.didTapEdit?()
                }
            )
            headerContainer.addSubview(editButton)
            editButton.autoAlignAxis(.horizontal, toSameAxisOf: titleLabel)
            editButton.autoPinEdge(toSuperviewMargin: .trailing)
            editButton.autoPinEdge(.leading, to: .trailing, of: titleLabel, withOffset: 8, relation: .greaterThanOrEqual)
            editButton.setTitleColor(Theme.primaryTextColor, for: .normal)

            return headerContainer
        }()

        let note: String? = self.context.db.read { tx in
            guard
                let recipient = self.context.recipientDatabaseTable.fetchRecipient(
                    address: self.thread.contactAddress,
                    tx: tx
                ),
                let nicknameRecord = self.context.nicknameManager.fetchNickname(
                    for: recipient,
                    tx: tx
                )
            else { return nil }
            return nicknameRecord.note
        }

        self.noteTextView.text = note

        let section = OWSTableSection(
            items: [
                self.textViewItem(
                    self.noteTextView,
                    dataDetectorTypes: .all
                )
            ],
            headerView: header
        )

        let contents = OWSTableContents(sections: [section])

        self.setContents(contents, shouldReload: shouldReload)
        self.tableView.layoutIfNeeded()
    }
}
