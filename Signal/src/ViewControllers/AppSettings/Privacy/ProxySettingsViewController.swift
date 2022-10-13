//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

class ProxySettingsViewController: OWSTableViewController2, OWSNavigationView {
    private var useProxy = SignalProxy.useProxy

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString(
            "PROXY_SETTINGS_TITLE",
            comment: "Title for the signal proxy settings"
        )

        updateTableContents()
        updateNavigationBar()
    }

    private var hasPendingChanges: Bool {
        useProxy != SignalProxy.useProxy || host != SignalProxy.host
    }

    private var host: String? {
        hostTextField.text?.nilIfEmpty
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
        textField.textContentType = .URL
        textField.delegate = self
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)

        return textField
    }()

    override func applyTheme() {
        super.applyTheme()

        updateTableContents()
    }

    @objc
    func updateTableContents() {
        let contents = OWSTableContents()
        defer { self.contents = contents }

        let useProxy = self.useProxy

        let useProxySection = OWSTableSection()
        useProxySection.footerAttributedTitle = .composed(of: [
            NSLocalizedString("USE_PROXY_EXPLANATION", comment: "Explanation of when you should use a signal proxy"),
            " ",
            CommonStrings.learnMore.styled(with: .link(URL(string: "https://support.signal.org/hc/en-us/articles/360056052052-Proxy-Support")!))
        ]).styled(
            with: .font(.ows_dynamicTypeCaption1Clamped),
            .color(Theme.secondaryTextAndIconColor)
        )
        useProxySection.add(.switch(
            withText: NSLocalizedString("USE_PROXY_BUTTON", comment: "Button to activate the signal proxy"),
            isOn: { [weak self] in
                self?.useProxy ?? false
            },
            target: self,
            selector: #selector(didToggleUseProxy)
        ))
        contents.addSection(useProxySection)

        let proxyAddressSection = OWSTableSection()
        proxyAddressSection.headerAttributedTitle = NSLocalizedString("PROXY_ADDRESS", comment: "The title for the address of the signal proxy").styled(
            with: .color((Theme.isDarkThemeEnabled ? UIColor.ows_gray05 : UIColor.ows_gray90).withAlphaComponent(useProxy ? 1 : 0.25)),
            .font(UIFont.ows_dynamicTypeBodyClamped.ows_semibold)
        )
        proxyAddressSection.add(.init(
            customCellBlock: { [weak self] in
                let cell = OWSTableItem.newCell()
                cell.selectionStyle = .none
                guard let self = self else { return cell }

                cell.contentView.addSubview(self.hostTextField)
                self.hostTextField.autoPinEdgesToSuperviewMargins()

                if !useProxy {
                    cell.isUserInteractionEnabled = false
                    cell.contentView.alpha = 0.25
                }

                return cell
            },
            actionBlock: {}
        ))
        contents.addSection(proxyAddressSection)

        let shareSection = OWSTableSection()
        shareSection.add(.init(
            customCellBlock: {
                let cell = OWSTableItem.buildImageNameCell(image: Theme.iconImage(.messageActionShare24), itemName: CommonStrings.shareButton)
                cell.selectionStyle = .none

                if !useProxy {
                    cell.isUserInteractionEnabled = false
                    cell.contentView.alpha = 0.25
                }

                return cell
            },
            actionBlock: { [weak self] in
                guard let self = self else { return }
                guard !self.notifyForInvalidHostIfNecessary() else { return }
                AttachmentSharing.showShareUI(for: URL(string: "https://signal.tube#\(self.host ?? "")")!, sender: self.view)
            }
        ))
        contents.addSection(shareSection)
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

    private func notifyForInvalidHostIfNecessary() -> Bool {
        guard !SignalProxy.isValidProxyFragment(host) else { return false }

        // allow saving an empty host when the proxy is off
        if !useProxy && host == nil { return false }

        presentToast(text: NSLocalizedString("INVALID_PROXY_HOST_ERROR", comment: "The provided proxy host address is not valid"))

        return true
    }

    @objc
    private func didTapSave() {
        hostTextField.resignFirstResponder()

        guard !notifyForInvalidHostIfNecessary() else { return }

        databaseStorage.write { transaction in
            SignalProxy.setProxyHost(host: self.host, useProxy: self.useProxy, transaction: transaction)
        }

        guard useProxy else {
            if navigationController?.viewControllers.count == 1 {
                dismiss(animated: true)
            } else {
                updateNavigationBar()
            }
            return
        }

        ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { modal in
            ProxyConnectionChecker.checkConnectionAndNotify { connected in
                modal.dismiss {
                    if connected {
                        if self.navigationController?.viewControllers.count == 1 {
                            self.presentingViewController?.presentToast(text: NSLocalizedString("PROXY_CONNECTED_SUCCESSFULLY", comment: "The provided proxy connected successfully"))
                            self.dismiss(animated: true)
                        } else {
                            self.presentToast(text: NSLocalizedString("PROXY_CONNECTED_SUCCESSFULLY", comment: "The provided proxy connected successfully"))
                            self.updateNavigationBar()
                        }
                    } else {
                        self.presentToast(text: NSLocalizedString("PROXY_FAILED_TO_CONNECT", comment: "The provided proxy couldn't connect"))
                        Self.databaseStorage.write { transaction in
                            SignalProxy.setProxyHost(host: self.host, useProxy: false, transaction: transaction)
                        }
                        self.updateTableContents()
                    }
                }
            }
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

extension ProxySettingsViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if hasPendingChanges {
            didTapSave()
        } else {
            textField.resignFirstResponder()
        }
        return false
    }
}
