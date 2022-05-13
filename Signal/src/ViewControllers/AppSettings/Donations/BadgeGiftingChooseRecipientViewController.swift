//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

// TODO(evanhahn) This view is unfinished.
class BadgeGiftingChooseRecipientViewController: OWSViewController {
    private let recipientPicker = RecipientPickerViewController()

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("BADGE_GIFTING_CHOOSE_RECIPIENT_TITLE",
                                  comment: "Title on the screen where you choose a gift badge's recipient")

        recipientPicker.allowsAddByPhoneNumber = false
        recipientPicker.shouldHideLocalRecipient = true
        recipientPicker.allowsSelectingUnregisteredPhoneNumbers = false
        recipientPicker.shouldShowGroups = false
        recipientPicker.showUseAsyncSelection = false
        recipientPicker.delegate = self
        addChild(recipientPicker)
        view.addSubview(recipientPicker.view)
        recipientPicker.view.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .leading)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .trailing)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .bottom)

        rerender()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        recipientPicker.applyTheme(to: self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        recipientPicker.removeTheme(from: self)
    }

    override func themeDidChange() {
        super.themeDidChange()
        rerender()
    }

    private func rerender() {
        view.backgroundColor = OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: true)
    }
}

extension BadgeGiftingChooseRecipientViewController: RecipientPickerDelegate {
    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         canSelectRecipient recipient: PickedRecipient) -> RecipientPickerRecipientState {
        guard let address = recipient.address, address.isValid, !address.isLocalAddress else {
            owsFailDebug("Invalid recipient")
            return .unknownError
        }

        // TODO(evanhahn): Fail if they lack the capability.

        return .canBeSelected
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         didSelectRecipient recipient: PickedRecipient) {
        guard let address = recipient.address, address.isValid, !address.isLocalAddress else {
            owsFailDebug("Invalid recipient")
            dismiss(animated: true)
            return
        }

        print("TODO(evanhahn): Send badge to this person")
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         willRenderRecipient recipient: PickedRecipient) {}

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         prepareToSelectRecipient recipient: PickedRecipient) -> AnyPromise {
        return AnyPromise(Promise.value(()))
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         showInvalidRecipientAlert recipient: PickedRecipient) {}

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         accessoryMessageForRecipient recipient: PickedRecipient,
                         transaction: SDSAnyReadTransaction) -> String? { nil }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         attributedSubtitleForRecipient recipient: PickedRecipient,
                         transaction: SDSAnyReadTransaction) -> NSAttributedString? {
        // TODO(evanhahn) Only show this if they lack the capability.
        NSLocalizedString("BADGE_GIFTING_CANNOT_SEND_BADGE_SUBTITLE",
                          comment: "Indicates that a contact cannot receive badges because they need to update Signal").attributedString()
    }

    func recipientPickerTableViewWillBeginDragging(_ recipientPickerViewController: RecipientPickerViewController) {}

    func recipientPickerNewGroupButtonWasPressed() {}

    func recipientPickerCustomHeaderViews() -> [UIView] { [] }
}
