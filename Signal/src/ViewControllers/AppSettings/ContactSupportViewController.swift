//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc(OWSSupportConstants)
@objcMembers class SupportConstants: NSObject {
    static let supportURL = URL(string: "https://support.signal.org/")!
    static let debugLogsInfoURL = URL(string: "https://support.signal.org/hc/articles/360007318591")!
    static let supportEmail = "support@signal.org"
}

@objc(OWSContactSupportViewController)
final class ContactSupportViewController: OWSTableViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.keyboardDismissMode = .interactive
        tableView.separatorInsetReference = .fromCellEdges
        tableView.separatorInset = .zero
        useThemeBackgroundColors = false

        rebuildTableContents()
        setupNavigationBar()
        setupDataProviderViews()
        applyTheme()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardFrameChange),
                                               name: UIResponder.keyboardWillChangeFrameNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardFrameChange),
                                               name: UIResponder.keyboardDidChangeFrameNotification,
                                               object: nil)
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
        debugSwitch.isOn = true
    }

    func setupNavigationBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: CommonStrings.cancelButton,
            style: .plain,
            target: self,
            action: #selector(didTapCancel)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: CommonStrings.nextButton,
            style: .done,
            target: self,
            action: #selector(didTapNext)
        )
        navigationItem.rightBarButtonItem?.isEnabled = false
    }

    @objc override func applyTheme() {
        super.applyTheme()
        navigationItem.rightBarButtonItem?.tintColor = Theme.accentBlueColor

        // Rebuild the contents to force them to update their theme
        rebuildTableContents()
    }

    func rebuildTableContents() {
        contents = constructContents()
    }

    // MARK: - View transitions

    @objc func keyboardFrameChange(_ notification: NSNotification) {
        guard let keyboardEndFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            owsFailDebug("Missing keyboard frame info")
            return
        }
        let tableViewSafeArea = tableView.bounds.inset(by: tableView.safeAreaInsets)
        let keyboardFrameInTableView = tableView.convert(keyboardEndFrame, from: nil)
        let intersectionHeight = keyboardFrameInTableView.intersection(tableViewSafeArea).height

        tableView.contentInset.bottom = intersectionHeight
        tableView.scrollIndicatorInsets.bottom = intersectionHeight
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: { (_) in
            self.scrollToFocus(animated: true)
        }, completion: nil)
    }

    var showSpinnerOnNextButton = false {
        didSet {
            guard showSpinnerOnNextButton else {
                navigationItem.rightBarButtonItem?.customView = nil
                return
            }

            let indicatorStyle: UIActivityIndicatorView.Style
            if #available(iOS 13, *) {
                indicatorStyle = .medium
            } else {
                indicatorStyle = Theme.isDarkThemeEnabled ? .white : .gray
            }
            let spinner = UIActivityIndicatorView(style: indicatorStyle)
            spinner.startAnimating()

            let label = UILabel()
            label.text = NSLocalizedString("SUPPORT_LOG_UPLOAD_IN_PROGRESS",
                                           comment: "A string in the navigation bar indicating that the support request is uploading logs")
            label.textColor = Theme.secondaryTextAndIconColor

            let stackView = UIStackView(arrangedSubviews: [label, spinner])
            stackView.spacing = 4
            navigationItem.rightBarButtonItem?.customView = stackView
        }
    }

    // MARK: - Actions

    @objc func didTapCancel() {
        currentEmailComposeOperation?.cancel()
        navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
    }

    var currentEmailComposeOperation: ComposeSupportEmailOperation?
    @objc func didTapNext() {
        var emailRequest = SupportEmailModel()
        emailRequest.userDescription = descriptionField.text
        emailRequest.emojiMood = emojiPicker.selectedMood
        emailRequest.debugLogPolicy = debugSwitch.isOn ? .attemptUpload : .none
        let operation = ComposeSupportEmailOperation(model: emailRequest)
        currentEmailComposeOperation = operation
        showSpinnerOnNextButton = true

        firstly { () -> Promise<Void> in
            operation.perform(on: .sharedUserInitiated)

        }.done(on: .main) { _ in
            self.navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)

        }.catch(on: .main) { error in
            let alertTitle = error.localizedDescription
            let alertMessage = NSLocalizedString("SUPPORT_EMAIL_ERROR_ALERT_DESCRIPTION",
                                                 comment: "Message for alert dialog presented when a support email failed to send")
            OWSActionSheets.showActionSheet(title: alertTitle, message: alertMessage)

        }.finally(on: .main) {
            self.currentEmailComposeOperation = nil
            self.showSpinnerOnNextButton = false

        }
    }
}

// MARK: - <SupportRequestTextViewDelegate>

extension ContactSupportViewController: SupportRequestTextViewDelegate, UIScrollViewDelegate {

    func textViewDidUpdateSelection(_ textView: SupportRequestTextView) {
        scrollToFocus(animated: true)
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
                self.scrollToFocus(animated: false)
            }
        }
    }

    /// Ensures the currently focused area is scrolled into the visible content inset
    /// If it's already visible, this will do nothing
    func scrollToFocus(animated: Bool) {
        let visibleRect = tableView.bounds.inset(by: tableView.adjustedContentInset)
        let rawCursorFocusRect = descriptionField.getUpdatedFocusLine()
        let cursorFocusRect = tableView.convert(rawCursorFocusRect, from: descriptionField)
        let paddedCursorRect = cursorFocusRect.insetBy(dx: 0, dy: -6)

        let entireContentFits = tableView.contentSize.height <= visibleRect.height
        let focusRect = entireContentFits ? visibleRect : paddedCursorRect

        // If we have a null rect, there's nowhere to scroll to
        // If the focusRect is already visible, there's no need to scroll
        guard !focusRect.isNull else { return }
        guard !visibleRect.contains(focusRect) else { return }

        let targetYOffset: CGFloat
        if focusRect.minY < visibleRect.minY {
            targetYOffset = focusRect.minY - tableView.adjustedContentInset.top
        } else {
            let bottomEdgeOffset = tableView.height - tableView.adjustedContentInset.bottom
            targetYOffset = focusRect.maxY - bottomEdgeOffset
        }
        tableView.setContentOffset(CGPoint(x: 0, y: targetYOffset), animated: animated)
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
                }),

                // Debug log switch
                OWSTableItem(customCell: createDebugLogCell(), customRowHeight: UITableView.automaticDimension),

                // FAQ prompt
                OWSTableItem(customCellBlock: {
                    let cell = OWSTableItem.newCell()
                    cell.textLabel?.font = UIFont.ows_dynamicTypeBody
                    cell.textLabel?.adjustsFontForContentSizeCategory = true
                    cell.textLabel?.numberOfLines = 0
                    cell.textLabel?.text = faqPromptText
                    cell.textLabel?.textColor = Theme.accentBlueColor
                    return cell
                },
                   actionBlock: {
                    UIApplication.shared.open(SupportConstants.supportURL, options: [:])
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
        label.font = UIFont.ows_dynamicTypeBody
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textColor = Theme.primaryTextColor

        let infoButton = OWSButton(imageName: "help-outline-24", tintColor: Theme.secondaryTextAndIconColor) {
            UIApplication.shared.open(SupportConstants.debugLogsInfoURL, options: [:])
        }
        infoButton.accessibilityLabel = NSLocalizedString("DEBUG_LOG_INFO_BUTTON",
                                                          comment: "Accessibility label for the ? vector asset used to get info about debug logs")

        cell.contentView.addSubview(label)
        cell.contentView.addSubview(infoButton)
        cell.accessoryView = debugSwitch

        label.autoPinEdges(toSuperviewMarginsExcludingEdge: .trailing)
        label.setCompressionResistanceHigh()

        infoButton.autoPinHeightToSuperviewMargins()
        infoButton.autoPinLeading(toTrailingEdgeOf: label, offset: 6)
        infoButton.autoPinEdge(toSuperviewMargin: .trailing, relation: .greaterThanOrEqual)

        return cell
    }

    func createEmojiFooterView() -> UIView {
        let containerView = UIView()

        // These constants were pulled from OWSTableViewController to get things to line up right
        let horizontalEdgeInset: CGFloat = UIDevice.current.isPlusSizePhone ? 20 : 16
        containerView.directionalLayoutMargins.leading = horizontalEdgeInset
        containerView.directionalLayoutMargins.trailing = horizontalEdgeInset

        containerView.addSubview(emojiPicker)
        emojiPicker.autoPinEdges(toSuperviewMarginsExcludingEdge: .trailing)
        return containerView
    }
}
