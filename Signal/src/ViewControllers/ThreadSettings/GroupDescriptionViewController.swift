//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol GroupDescriptionViewControllerDelegate: AnyObject {
    func groupDescriptionViewControllerDidComplete(groupDescription: String?)
}

class GroupDescriptionViewController: OWSTableViewController2 {
    private let helper: GroupAttributesEditorHelper
    private let providedCurrentDescription: Bool

    weak var descriptionDelegate: GroupDescriptionViewControllerDelegate?

    private let options: Options
    struct Options: OptionSet {
        let rawValue: Int

        static let updateImmediately = Options(rawValue: 1 << 0)
        static let editable          = Options(rawValue: 1 << 1)
    }

    var isEditable: Bool { options.contains(.editable) }

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

    init(
        helper: GroupAttributesEditorHelper,
        groupDescriptionCurrent: String? = nil,
        options: Options = []
    ) {
        self.helper = helper
        self.options = options

        if let groupDescriptionCurrent = groupDescriptionCurrent {
            self.helper.groupDescriptionOriginal = groupDescriptionCurrent
            providedCurrentDescription = true
        } else {
            providedCurrentDescription = false
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
        helper.descriptionTextView.linkTextAttributes = [
            .foregroundColor: UIColor.link,
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
            if self.providedCurrentDescription {
                // don't assume the current group title applies
                // if a group description was directly provided.
                title = nil
            } else {
                title = groupName
            }
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
            navigationItem.leftBarButtonItem = .cancelButton(
                dismissingFrom: self,
                hasUnsavedChanges: { [weak self] in self?.helper.hasUnsavedChanges }
            )
        } else {
            navigationItem.leftBarButtonItem = .doneButton { [weak self] in
                self?.didTapDone()
            }
        }

        if helper.hasUnsavedChanges {
            owsAssertDebug(isEditable)
            if options.contains(.updateImmediately) {
                navigationItem.rightBarButtonItem = .button(
                    title: CommonStrings.setButton,
                    style: .done,
                    action: { [weak self] in
                        self?.didTapSet()
                    }
                )
            } else {
                navigationItem.rightBarButtonItem = .doneButton { [weak self] in
                    self?.didTapDone()
                }
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

        let section = OWSTableSection()
        descriptionTextView.isEditable = self.isEditable
        section.add(self.textViewItem(
            descriptionTextView,
            minimumHeight: self.isEditable ? 74 : nil,
            dataDetectorTypes: self.isEditable ? [] : .all
        ))

        if isEditable {
            section.footerTitle = OWSLocalizedString(
                "GROUP_DESCRIPTION_VIEW_EDIT_FOOTER",
                comment: "Footer text when editing the group description"
            )
        }

        contents.add(section)

        self.contents = contents
    }

    private func didTapDone() {
        helper.descriptionTextView.acceptAutocorrectSuggestion()
        descriptionDelegate?.groupDescriptionViewControllerDidComplete(groupDescription: helper.groupDescriptionCurrent)
        dismiss(animated: true)
    }

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

extension GroupDescriptionViewController: GroupAttributesEditorHelperDelegate, TextViewWithPlaceholderDelegate {
    func groupAttributesEditorContentsDidChange() {
        updateNavigation()
        textViewDidUpdateText(helper.descriptionTextView)
    }

    func groupAttributesEditorSelectionDidChange() {
        textViewDidUpdateSelection(helper.descriptionTextView)
    }
}
