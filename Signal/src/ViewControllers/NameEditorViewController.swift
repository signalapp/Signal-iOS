//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI

/// Abstract class for a view controller with a text field used to edit the name
/// of something. Subclass, override properties, and set `title` to use.
///
/// Subclasses should override:
/// - `nameByteLimit`
/// - `nameGlyphLimit`
/// - `placeholderText`
/// - `handleError(_:)`
class NameEditorViewController: OWSTableViewController2 {
    class var nameByteLimit: Int { owsFail("Must be implemented by subclasses") }
    class var nameGlyphLimit: Int { owsFail("Must be implemented by subclasses") }

    var placeholderText: String? { nil }

    private lazy var nameField = OWSTextField(
        placeholder: self.placeholderText,
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

    private let oldName: String
    private let setNewName: (String) async throws -> Void

    private var isPresentedInSheet = false

    init(oldName: String, setNewName: @escaping (String) async throws -> Void) {
        self.oldName = oldName
        self.setNewName = setNewName
        super.init()
        self.shouldAvoidKeyboard = true
    }

    func presentInNavController(from viewController: UIViewController, forceDarkMode: Bool = false) {
        self.isPresentedInSheet = true
        let navigationController = OWSNavigationController(rootViewController: self)
        if forceDarkMode {
            self.forceDarkMode = true
            navigationController.overrideUserInterfaceStyle = .dark
        }
        viewController.presentFormSheet(navigationController, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if isPresentedInSheet {
            self.navigationItem.leftBarButtonItem = .cancelButton(
                dismissingFrom: self,
                hasUnsavedChanges: { [unowned self] in self.hasUnsavedChanges }
            )
        }
        self.navigationItem.rightBarButtonItem = .doneButton { [unowned self] in self.didTapDone() }
        self.navigationItem.rightBarButtonItem?.isEnabled = false

        self.nameField.text = self.oldName

        self.contents = OWSTableContents(sections: [
            OWSTableSection(items: [.textFieldItem(
                self.nameField,
                textColor: UIColor.Signal.label
            )]),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // It's laggy to assign first responder while pushing in a navigation
        // controller, but it's okay while presenting a sheet.
        if isPresentedInSheet {
            self.nameField.becomeFirstResponder()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !isPresentedInSheet {
            self.nameField.becomeFirstResponder()
        }
    }

    override var isModalInPresentation: Bool {
        get { hasUnsavedChanges }
        set {}
    }

    private func updateHasUnsavedChanges() {
        self.hasUnsavedChanges = self.nameField.text != self.oldName
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
        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            presentationDelay: 0.25,
            asyncBlock: { [weak self] modal in
                guard let self else { return }
                let updateResult = await Result {
                    try await self.setNewName(self.nameField.text!)
                }
                modal.dismissIfNotCanceled { [weak self] in
                    do {
                        _ = try updateResult.get()
                        if self?.isPresentedInSheet ?? false {
                            self?.dismiss(animated: true)
                        } else {
                            self?.nameField.resignFirstResponder()
                            self?.navigationController?.popViewController(animated: true)
                        }
                    } catch {
                        self?.handleError(error)
                    }
                }
            }
        )
    }

    func handleError(_ error: any Error) {
    }
}

extension NameEditorViewController: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        return TextFieldHelper.textField(
            textField,
            shouldChangeCharactersInRange: range,
            replacementString: string,
            maxByteCount: Self.nameByteLimit,
            maxGlyphCount: Self.nameGlyphLimit
        )
    }
}
