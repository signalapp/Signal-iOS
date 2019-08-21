//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
protocol FindByPhoneNumberDelegate: class {
    func findByPhoneNumber(_ findByPhoneNumber: FindByPhoneNumberViewController,
                           didSelectAddress address: SignalServiceAddress)
}

@objc
class FindByPhoneNumberViewController: SelectRecipientViewController {
    weak var findByPhoneNumberDelegate: FindByPhoneNumberDelegate?
    let buttonText: String?
    let requiresRegisteredNumber: Bool

    @objc
    init(delegate: FindByPhoneNumberDelegate, buttonText: String?, requiresRegisteredNumber: Bool) {
        self.findByPhoneNumberDelegate = delegate
        self.buttonText = buttonText
        self.requiresRegisteredNumber = requiresRegisteredNumber
        super.init(nibName: nil, bundle: nil)
        self.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("NEW_NONCONTACT_CONVERSATION_VIEW_TITLE",
                                  comment: "Title for the 'new non-contact conversation' view.")
    }
}

extension FindByPhoneNumberViewController: SelectRecipientViewControllerDelegate {
    func phoneNumberButtonText() -> String {
        return buttonText ?? NSLocalizedString("NEW_NONCONTACT_CONVERSATION_VIEW_BUTTON",
                                               comment: "A label for the 'add by phone number' button in the 'new non-contact conversation' view")
    }

    func addressWasSelected(_ address: SignalServiceAddress) {
        findByPhoneNumberDelegate?.findByPhoneNumber(self, didSelectAddress: address)
    }

    func shouldHideLocalNumber() -> Bool {
        return true
    }

    func shouldHideContacts() -> Bool {
        return true
    }

    func shouldValidatePhoneNumbers() -> Bool {
        return requiresRegisteredNumber
    }

    func phoneNumberSectionTitle() -> String {
        return ""
    }

    func contactsSectionTitle() -> String {
        return ""
    }

    func canSignalAccountBeSelected(_ signalAccount: SignalAccount) -> Bool {
        owsFailDebug("should never be called")
        return false
    }

    func signalAccountWasSelected(_ signalAccount: SignalAccount) {
        owsFailDebug("should never be called")
        return
    }

    func accessoryMessage(for signalAccount: SignalAccount) -> String? {
        owsFailDebug("should never be called")
        return nil
    }
}
