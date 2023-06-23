//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

class ProxyLinkSheetViewController: OWSTableSheetViewController {
    let url: URL

    init?(url: URL) {
        guard SignalProxy.isValidProxyLink(url) else { return nil }
        self.url = url
        super.init()
    }

    required init() {
        fatalError("init() has not been implemented")
    }

    override func updateTableContents(shouldReload: Bool = true) {
        let contents = OWSTableContents()
        defer { tableViewController.setContents(contents, shouldReload: shouldReload) }

        let proxyHost = url.fragment!

        let avatarSection = OWSTableSection()
        avatarSection.hasBackground = false
        contents.add(avatarSection)
        avatarSection.add(.init(customCellBlock: {
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none

            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFit
            imageView.image = UIImage(named: "proxy_avatar")
            imageView.autoSetDimension(.height, toSize: 96)

            let titleLabel = UILabel()
            titleLabel.font = .dynamicTypeHeadline
            titleLabel.text = "Proxy Server"
            titleLabel.textColor = Theme.primaryTextColor
            titleLabel.textAlignment = .center

            let stackView = UIStackView(arrangedSubviews: [imageView, titleLabel])
            stackView.axis = .vertical
            stackView.spacing = 12
            stackView.alignment = .center

            cell.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewMargins()

            return cell
        }))

        let addressSection = OWSTableSection()
        addressSection.hasBackground = false
        addressSection.headerTitle = OWSLocalizedString("PROXY_ADDRESS", comment: "The title for the address of the signal proxy")
        contents.add(addressSection)
        addressSection.add(.label(withText: proxyHost))

        let actionsSection = OWSTableSection()
        actionsSection.hasBackground = false
        actionsSection.headerTitle = OWSLocalizedString("DO_YOU_WANT_TO_USE_PROXY", comment: "Title for the proxy confirmation")
        contents.add(actionsSection)
        actionsSection.add(.init(customCellBlock: { [weak self] in
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none

            guard let self = self else { return cell }

            let stackView = UIStackView(arrangedSubviews: [
                self.button(
                    title: CommonStrings.cancelButton,
                    titleColor: Theme.primaryTextColor,
                    touchHandler: { [weak self] in
                        self?.dismiss(animated: true)
                    }),
                self.button(
                    title: OWSLocalizedString("USE_PROXY_BUTTON", comment: "Button to activate the signal proxy"),
                    titleColor: .ows_accentBlue,
                    touchHandler: { [weak self] in
                        Self.databaseStorage.write {
                            SignalProxy.setProxyHost(host: proxyHost, useProxy: true, transaction: $0)
                        }

                        let presentingVC = self?.presentingViewController
                        ProxyConnectionChecker.checkConnectionAndNotify { connected in
                            if connected {
                                presentingVC?.presentToast(text: OWSLocalizedString("PROXY_CONNECTED_SUCCESSFULLY", comment: "The provided proxy connected successfully"))
                            } else {
                                presentingVC?.presentToast(text: OWSLocalizedString("PROXY_FAILED_TO_CONNECT", comment: "The provided proxy couldn't connect"))
                                Self.databaseStorage.write { transaction in
                                    SignalProxy.setProxyHost(host: proxyHost, useProxy: false, transaction: transaction)
                                }
                            }
                        }

                        self?.dismiss(animated: true)
                    })
            ])
            stackView.axis = .horizontal
            stackView.spacing = 12
            stackView.distribution = .fillEqually
            cell.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewMargins()

            return cell
        }))
    }

    private func button(title: String, titleColor: UIColor, touchHandler: @escaping () -> Void) -> OWSFlatButton {
        let flatButton = OWSFlatButton()
        flatButton.setTitle(title: title, font: UIFont.dynamicTypeBodyClamped.semibold(), titleColor: titleColor)
        flatButton.setBackgroundColors(upColor: tableViewController.cellBackgroundColor)
        flatButton.setPressedBlock(touchHandler)
        flatButton.useDefaultCornerRadius()
        flatButton.autoSetDimension(.height, toSize: 48)
        return flatButton
    }
}
