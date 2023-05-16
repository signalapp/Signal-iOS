//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

protocol GroupDescriptionViewControllerDelegate: AnyObject {
    func groupDescriptionViewControllerDidComplete(groupDescription: String?)
}

class GroupDescriptionViewController: OWSTableViewController2 {
    private let helper: GroupAttributesEditorHelper

    weak var descriptionDelegate: GroupDescriptionViewControllerDelegate?

    private let options: Options
    struct Options: OptionSet {
        let rawValue: Int

        static let updateImmediately = Options(rawValue: 1 << 0)
        static let editable          = Options(rawValue: 1 << 1)
    }

    var isEditable: Bool { options.contains(.editable) }

    convenience init(groupModel: TSGroupModel) {
        self.init(groupModel: groupModel, options: [])
    }

    convenience init(
        groupModel: TSGroupModel,
        groupDescriptionCurrent: String? = nil,
        options: Options
    ) {
        self.init(
            helper: GroupAttributesEditorHelper(groupModel: groupModel),
            groupDescriptionCurrent: groupDescriptionCurrent,
            options: options
        )
    }

    required init(
        helper: GroupAttributesEditorHelper,
        groupDescriptionCurrent: String? = nil,
        options: Options = []
    ) {
        self.helper = helper
        self.options = options

        if let groupDescriptionCurrent = groupDescriptionCurrent {
            self.helper.groupDescriptionOriginal = groupDescriptionCurrent
        }

        super.init()

        shouldAvoidKeyboard = true
    }

    // MARK: -

    override func viewDidLoad() {
        super.viewDidLoad()

        helper.delegate = self
        helper.buildContents()

        updateNavigation()
        updateTableContents()
    }

    override func themeDidChange() {
        super.themeDidChange()

        helper.descriptionTextView.linkTextAttributes = [
            .foregroundColor: Theme.primaryTextColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: { (_) in
            self.helper.descriptionTextView.scrollToFocus(in: self.tableView, animated: true)
        }, completion: nil)
    }

    // Don't allow interactive dismiss when there are unsaved changes.
    override var isModalInPresentation: Bool {
        get { helper.hasUnsavedChanges }
        set {}
    }

    private func updateNavigation() {
        let currentGlyphCount = (helper.groupDescriptionCurrent ?? "").glyphCount
        let remainingGlyphCount = max(0, GroupManager.maxGroupDescriptionGlyphCount - currentGlyphCount)

        if !isEditable, let groupName = helper.groupNameCurrent {
            title = groupName
        } else if isEditable, remainingGlyphCount <= 100 {
            let titleFormat = OWSLocalizedString(
                "GROUP_DESCRIPTION_VIEW_TITLE_FORMAT",
                comment: "Title for the group description view. Embeds {{ the number of characters that can be added to the description without hitting the length limit }}."
            )
            title = String(format: titleFormat, OWSFormat.formatInt(remainingGlyphCount))
        } else {
            title = OWSLocalizedString(
                "GROUP_DESCRIPTION_VIEW_TITLE",
                comment: "Title for the group description view."
            )
        }

        if isEditable {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .cancel,
                target: self,
                action: #selector(didTapCancel),
                accessibilityIdentifier: "cancel_button"
            )
        } else {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .done,
                target: self,
                action: #selector(didTapDone),
                accessibilityIdentifier: "done_button"
            )
        }

        if helper.hasUnsavedChanges {
            owsAssertDebug(isEditable)
            if options.contains(.updateImmediately) {
                navigationItem.rightBarButtonItem = UIBarButtonItem(
                    title: CommonStrings.setButton,
                    style: .done,
                    target: self,
                    action: #selector(didTapSet),
                    accessibilityIdentifier: "set_button"
                )
            } else {
                navigationItem.rightBarButtonItem = UIBarButtonItem(
                    barButtonSystemItem: .done,
                    target: self,
                    action: #selector(didTapDone),
                    accessibilityIdentifier: "done_button"
                )
            }
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateNavigation()

        if isEditable {
            helper.descriptionTextView.becomeFirstResponder()
        }
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let descriptionTextView = helper.descriptionTextView
        let isEditable = self.isEditable

        let section = OWSTableSection()
        section.add(.init(
            customCellBlock: {
                let cell = OWSTableItem.newCell()

                cell.selectionStyle = .none

                cell.contentView.addSubview(descriptionTextView)
                descriptionTextView.autoPinEdgesToSuperviewMargins()

                if isEditable {
                    descriptionTextView.isEditable = true
                    descriptionTextView.dataDetectorTypes = []
                    descriptionTextView.autoSetDimension(.height, toSize: 74, relation: .greaterThanOrEqual)
                } else {
                    descriptionTextView.isEditable = false
                    descriptionTextView.dataDetectorTypes = .all
                }

                return cell
            },
            actionBlock: {
                if isEditable {
                    descriptionTextView.becomeFirstResponder()
                }
            }
        ))

        if isEditable {
            section.footerTitle = OWSLocalizedString(
                "GROUP_DESCRIPTION_VIEW_EDIT_FOOTER",
                comment: "Footer text when editing the group description"
            )
        }

        contents.addSection(section)

        self.contents = contents
    }

    @objc
    private func didTapCancel() {
        guard helper.hasUnsavedChanges else {
            dismiss(animated: true)
            return
        }

        OWSActionSheets.showPendingChangesActionSheet(discardAction: { [weak self] in
            self?.dismiss(animated: true)
        })
    }

    @objc
    private func didTapDone() {
        helper.descriptionTextView.acceptAutocorrectSuggestion()
        descriptionDelegate?.groupDescriptionViewControllerDidComplete(groupDescription: helper.groupDescriptionCurrent)
        dismiss(animated: true)
    }

    @objc
    private func didTapSet() {
        guard isEditable, helper.hasUnsavedChanges else {
            return owsFailDebug("Unexpectedly trying to set")
        }

        helper.updateGroupIfNecessary(fromViewController: self) { [weak self] in
            guard let self = self else { return }
            self.descriptionDelegate?.groupDescriptionViewControllerDidComplete(
                groupDescription: self.helper.groupDescriptionCurrent
            )
            self.dismiss(animated: true)
        }
    }
}

extension GroupDescriptionViewController: GroupAttributesEditorHelperDelegate {
    func groupAttributesEditorContentsDidChange() {
        updateNavigation()

        // Kick the tableview so it recalculates sizes
        UIView.performWithoutAnimation {
            tableView.performBatchUpdates(nil) { (_) in
                // And when the size changes have finished, make sure we're scrolled
                // to the focused line
                self.helper.descriptionTextView.scrollToFocus(in: self.tableView, animated: false)
            }
        }
    }

    func groupAttributesEditorSelectionDidChange() {
        helper.descriptionTextView.scrollToFocus(in: tableView, animated: true)
    }
}
