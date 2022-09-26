//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

class ProxySettingsViewController: OWSTableViewController2, OWSNavigationView {
    private var useProxy = SignalProxy.useProxy

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("USE_PROXY_BUTTON", comment: "Button to activate the signal proxy")

        updateTableContents()
        updateNavigationBar()
    }

    private var hasPendingChanges: Bool {
        useProxy != SignalProxy.useProxy || hostTextField.text != SignalProxy.host
    }

    private func updateNavigationBar() {
        if navigationController?.viewControllers.count == 1 {
            navigationItem.leftBarButtonItem = .init(
                barButtonSystemItem: .cancel,
                target: self,
                action: #selector(didTapCancel)
            )
        }

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(didTapSave)
        )
        navigationItem.rightBarButtonItem?.isEnabled = hasPendingChanges
    }

    private lazy var hostTextField: UITextField = {
        let textField = UITextField()

        textField.text = SignalProxy.host
        textField.font = .ows_dynamicTypeBody
        textField.backgroundColor = .clear
        textField.placeholder = OWSLocalizedString(
            "PROXY_PLACEHOLDER",
            comment: "Placeholder text for signal proxy host"
        )
        textField.returnKeyType = .done
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)

        return textField
    }()

    func updateTableContents() {
        let contents = OWSTableContents()
        defer { self.contents = contents }

        let useProxySection = OWSTableSection()
        useProxySection.footerTitle = NSLocalizedString("USE_PROXY_EXPLANATION", comment: "Explanation of when you should use a signal proxy")
        useProxySection.add(.switch(
            withText: NSLocalizedString("USE_PROXY_BUTTON", comment: "Button to activate the signal proxy"),
            isOn: { [weak self] in
                self?.useProxy ?? false
            },
            target: self,
            selector: #selector(didToggleUseProxy)
        ))
        contents.addSection(useProxySection)

        if useProxy {

            let proxyAddressSection = OWSTableSection()
            proxyAddressSection.headerTitle = NSLocalizedString("PROXY_ADDRESS", comment: "The title for the address of the signal proxy")
            proxyAddressSection.add(.init(
                customCellBlock: { [weak self] in
                    let cell = OWSTableItem.newCell()
                    cell.selectionStyle = .none
                    guard let self = self else { return cell }

                    cell.contentView.addSubview(self.hostTextField)
                    self.hostTextField.autoPinEdgesToSuperviewMargins()

                    return cell
                },
                actionBlock: {}
            ))
            contents.addSection(proxyAddressSection)

            let shareSection = OWSTableSection()
            shareSection.add(.actionItem(
                icon: .messageActionShare,
                name: CommonStrings.shareButton,
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "share"),
                actionBlock: { [weak self] in
                    guard let self = self else { return }
                    AttachmentSharing.showShareUI(for: URL(string: "https://signal.tube#\(self.hostTextField.text ?? "")")!, sender: self.view)
                }))
            contents.addSection(shareSection)

        }
    }

    @objc
    private func didToggleUseProxy(_ sender: UISwitch) {
        useProxy = sender.isOn
        updateTableContents()
        updateNavigationBar()
    }

    @objc
    private func textFieldDidChange() {
        updateNavigationBar()
    }

    @objc
    private func didTapSave() {
        databaseStorage.write { transaction in
            SignalProxy.setProxyHost(host: self.hostTextField.text, useProxy: self.useProxy, transaction: transaction)
        }
        if navigationController?.viewControllers.count == 1 {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    @objc
    private func didTapCancel() {
        if hasPendingChanges {
            OWSActionSheets.showPendingChangesActionSheet { [weak self] in
                self?.dismiss(animated: true)
            }
        } else {
            dismiss(animated: true)
        }
    }

    func shouldCancelNavigationBack() -> Bool {
        if hasPendingChanges {
            OWSActionSheets.showPendingChangesActionSheet { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
            return true
        } else {
            return false
        }
    }
}
