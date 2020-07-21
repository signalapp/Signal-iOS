//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSContactSupportViewController)
class ContactSupportViewController: OWSTableViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        owsAssert(navigationController != nil, "Expecting to be presented in a navigation controller")

        tableView.keyboardDismissMode = .interactive
        useThemeBackgroundColors = false     // TODO ask myles about background color

        setupNavigationBar()
        setupDataProviderViews()
        applyTheme()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardFrameWillChange),
                                               name: UIResponder.keyboardWillChangeFrameNotification,
                                               object: nil)
    }

    private lazy var declaredContentDefinition = constructContents()
    override var contents: OWSTableContents {
        get {
            return declaredContentDefinition
        }
        set {
            // LSP violation
            owsFailDebug("Assigning to contents overwrites the content declaration")
        }
    }

    // MARK: - Data providers
    // Any views that provide model information are instantiated by the view controller directly
    // Views that are just chrome are put together in the `constructTableContents()` function

    private let descriptionField = SupportRequestTextView()
    private let debugSwitch = UISwitch()
    private let emojiPicker = EmojiMoodPickerView()

    func setupDataProviderViews() {
        descriptionField.delegate = self
        descriptionField.placeholderText = NSLocalizedString("SUPPORT_DESCRIPTION_PLACEHOLDER",
                                                             comment: "Placeholder string for support description")
        debugSwitch.onTintColor = nil       // Override +UIAppearance default

    }

    func setupNavigationBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: CommonStrings.cancelButton,
                                                           style: .plain,
                                                           target: self,
                                                           action: #selector(didTapCancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: CommonStrings.nextButton,
                                                            style: .done,
                                                            target: self,
                                                            action: #selector(didTapNext))
        navigationItem.rightBarButtonItem?.isEnabled = false
    }

    @objc override func applyTheme() {
        super.applyTheme()
        navigationItem.rightBarButtonItem?.tintColor = Theme.accentBlueColor
    }

    // MARK: - View transitions

    @objc func keyboardFrameWillChange(_ notification: NSNotification) {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            owsFailDebug("Missing keyboard frame info")
            return
        }
        let keyboardFrameInScrollView = tableView.convert(endFrame, from: nil)
        tableView.contentInset.bottom = keyboardFrameInScrollView.height
        tableView.scrollIndicatorInsets.bottom = keyboardFrameInScrollView.height
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: { (_) in
            self.scrollFocusedLineToVisible(animated: true)
        }, completion: nil)
    }

    // MARK: - Actions

    @objc func didTapCancel() {
        navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
    }

    @objc func didTapNext() {
    }
}

// MARK: - <SupportRequestTextViewDelegate>

extension ContactSupportViewController: SupportRequestTextViewDelegate, UIScrollViewDelegate {

    func textViewDidUpdateSelection(_ textView: SupportRequestTextView) {
        scrollFocusedLineToVisible(animated: true)
    }

    func textViewDidUpdateText(_ textView: SupportRequestTextView) {
        self.navigationItem.rightBarButtonItem?.isEnabled = (textView.text.count > 10)

        // Disable interactive presentation if the user has entered text
        if #available(iOS 13, *) {
            isModalInPresentation = (textView.text.count > 0)
        }

        // Kick the tableview so it recalculates sizes
        UIView.performWithoutAnimation {
            tableView.performBatchUpdates(nil) { (_) in
                // And when the size changes have finished, make sure we're scrolled
                // to the focused line
                self.scrollFocusedLineToVisible(animated: false)
            }
        }
    }

    /// Ensures the currently focused line is scrolled into the visible content inset
    /// If it's already visible, this will do nothing
    func scrollFocusedLineToVisible(animated: Bool) {
        // If we have a null rect, there's nowhere to scroll to
        let rawRect = descriptionField.getUpdatedFocusLine()
        guard !rawRect.isNull else { return }

        // We want to exit early if the selection rect is already visible. Using
        // -adjustedContentInset accounts for both safe area (home affordance +
        // navigation bar) and contentInset (keyboard frame)
        let focusedLineRect = tableView.convert(rawRect, from: descriptionField)
        let visibleRect = tableView.bounds.inset(by: tableView.adjustedContentInset)
        guard !visibleRect.contains(focusedLineRect) else { return }

        // A constant offset so we don't place our cursor *immediately* against our insets
        let selectionEdgePadding: CGFloat = 6

        // If our selection rect is closer to the bottom of the visible rect, we're going to
        // scroll so our selection rect's bottom edge is just above the adjusted content inset
        if focusedLineRect.center.y >= visibleRect.center.y {
            let bottomEdgeOffset = tableView.height - tableView.adjustedContentInset.bottom
            let desiredOffset = focusedLineRect.maxY - bottomEdgeOffset + selectionEdgePadding
            tableView.setContentOffset(CGPoint(x: 0, y: desiredOffset), animated: animated)

        } else {
            let topEdgeOffset = tableView.adjustedContentInset.top + selectionEdgePadding
            let desiredUpperBound = focusedLineRect.minY - topEdgeOffset
            tableView.setContentOffset(CGPoint(x: 0, y: desiredUpperBound), animated: animated)
        }
    }
}

// MARK: - Table view content builders

extension ContactSupportViewController {
    fileprivate func constructContents() -> OWSTableContents {

        let titleText = NSLocalizedString("HELP_CONTACT_US",
                                          comment: "Help item allowing the user to file a support request")
        let contactHeaderText = NSLocalizedString("SUPPORT_CONTACT_US_HEADER",
                                                  comment: "Header of support description field")
        let emojiHeaderText = NSLocalizedString("SUPPORT_EMOJI_PROMPT",
                                                comment: "Header for emoji mood selection")
        let faqPromptText = NSLocalizedString("SUPPORT_FAQ_PROMPT",
                                              comment: "Label in support request informing user about Signal FAQ")

        return OWSTableContents(title: titleText, sections: [

            OWSTableSection(title: contactHeaderText, items: [

                // Description field
                OWSTableItem(customCellBlock: {
                    let cell = OWSTableItem.newCell()
                    cell.contentView.addSubview(self.descriptionField)
                    self.descriptionField.autoPinEdgesToSuperviewMargins()
                    self.descriptionField.autoSetDimension(.height, toSize: 125, relation: .greaterThanOrEqual)
                    return cell
                }, customRowHeight: UITableView.automaticDimension),

                // Debug log switch
                OWSTableItem(customCell: createDebugLogCell(), customRowHeight: UITableView.automaticDimension),

                // FAQ prompt
                OWSTableItem(customCellBlock: {
                    let cell = OWSTableItem.newCell()
                    cell.textLabel?.text = faqPromptText
                    cell.textLabel?.textColor = Theme.accentBlueColor
                    return cell
                })
            ]),

            // The emoji picker is placed in the section footer to avoid tableview separators
            // As far as I can tell, there's no way for a grouped UITableView to not add separators
            // between the header and the first row without messing in the UITableViewCell's hierarchy
            //
            // UITableViewCell.separatorInset looks like it would work, but it only applies to separators
            // between cells, not between the header and the footer

            OWSTableSection(title: emojiHeaderText, footer: createEmojiFooterView())
        ])
    }

    func createDebugLogCell() -> UITableViewCell {
        let cell = OWSTableItem.newCell()

        let label = UILabel()
        label.text = NSLocalizedString("SUPPORT_INCLUDE_DEBUG_LOG",
                                       comment: "Label describing support switch to attach debug logs")
        label.font = OWSTableItem.primaryLabelFont
        label.textColor = Theme.primaryTextColor
        label.setContentHuggingHorizontalHigh()

        let infoAsset = UIImage(named: "help-outline-24")
        let infoButton = UIButton(type: .custom)
        infoButton.setImage(infoAsset, for: .normal)
        infoButton.setContentHuggingHorizontalHigh()
        infoButton.setCompressionResistanceHorizontalHigh()

        let spacer = UIView.hStretchingSpacer()

        let stackViewComponents = [label, infoButton, spacer]
        let stackView = UIStackView(arrangedSubviews: stackViewComponents)
        stackView.axis = .horizontal
        stackView.spacing = UIStackView.spacingUseSystem
        stackView.alignment = .center

        cell.contentView.addSubview(stackView)
        cell.accessoryView = self.debugSwitch

        stackView.autoPinEdgesToSuperviewMargins()
        return cell
    }

    func createEmojiFooterView() -> UIView {
        let containerView = UIView()
        let edgeInset: CGFloat = UIDevice.current.isPlusSizePhone ? 20 : 16
        containerView.layoutMargins = UIEdgeInsets(top: 0, leading: edgeInset, bottom: 0, trailing: edgeInset)

        let emojiPicker = EmojiMoodPickerView()
        containerView.addSubview(emojiPicker)
        emojiPicker.autoPinEdges(toSuperviewMarginsExcludingEdge: .trailing)
        return containerView
    }

}
