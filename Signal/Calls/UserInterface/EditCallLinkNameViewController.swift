//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI

class EditCallLinkNameViewController: OWSTableViewController2 {
    private enum Constants {
        /// Value taken from the spec.
        static let callNameByteLimit = 119
    }

    private lazy var callNameField = OWSTextField(
        placeholder: CallLinkState.defaultLocalizedName,
        returnKeyType: .done,
        autocapitalizationType: .words,
        clearButtonMode: .whileEditing,
        delegate: self,
        editingChanged: { [unowned self] in
            self.updateHasUnsavedChanges()
        },
        returnPressed: { [unowned self] in
            if hasUnsavedChanges { self.didTapDone() }
        }
    )

    private let oldCallName: String
    private let setNewCallName: (String) -> Void

    init(oldCallName: String, setNewCallName: @escaping (String) -> Void) {
        self.oldCallName = oldCallName
        self.setNewCallName = setNewCallName
        super.init()
        self.shouldAvoidKeyboard = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.leftBarButtonItem = .cancelButton(
            dismissingFrom: self,
            hasUnsavedChanges: { [unowned self] in self.hasUnsavedChanges }
        )
        self.navigationItem.rightBarButtonItem = .doneButton { [unowned self] in self.didTapDone() }
        self.navigationItem.rightBarButtonItem?.isEnabled = false

        self.callNameField.text = self.oldCallName

        self.contents = OWSTableContents(
            title: self.oldCallName.isEmpty ? CallStrings.addCallName : CallStrings.editCallName,
            sections: [
                OWSTableSection(items: [.textFieldItem(self.callNameField)]),
            ]
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.callNameField.becomeFirstResponder()
    }

    override var isModalInPresentation: Bool {
        get { hasUnsavedChanges }
        set {}
    }

    private func updateHasUnsavedChanges() {
        self.hasUnsavedChanges = self.callNameField.text != self.oldCallName
    }

    private var hasUnsavedChanges: Bool = false {
        didSet {
            if oldValue == hasUnsavedChanges {
                return
            }
            self.navigationItem.rightBarButtonItem?.isEnabled = hasUnsavedChanges
        }
    }

    private func didTapDone() {
        self.dismiss(animated: true)
        self.setNewCallName(self.callNameField.text!)
    }
}

extension EditCallLinkNameViewController: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        return TextFieldHelper.textField(
            textField,
            shouldChangeCharactersInRange: range,
            replacementString: string,
            maxByteCount: Constants.callNameByteLimit
        )
    }
}
