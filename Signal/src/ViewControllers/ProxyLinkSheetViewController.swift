//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class ProxyLinkSheetViewController: StackSheetViewController {
    private let url: URL

    init?(url: URL) {
        guard SignalProxy.isValidProxyLink(url) else { return nil }
        self.url = url
        super.init()
    }

    override var stackViewInsets: UIEdgeInsets {
        guard #available(iOS 26, *), UIDevice.current.hasIPhoneXNotch else { return super.stackViewInsets }

        // Reduced bottom margins looks better when there's a bottom safe area margin present.
        var insets = super.stackViewInsets
        insets.bottom = 0
        return insets
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        stackView.spacing = 24

        // Header
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.image = UIImage(named: "proxy_avatar")
        imageView.autoSetDimension(.height, toSize: 96)

        let titleLabel = UILabel.headlineLabel(
            text: OWSLocalizedString(
                "SIGNAL_PROXY",
                comment: "Title for the sheet presented when user taps on Signal Proxy link in chat.",
            ),
            semibold: true,
        )
        let questionLabel = UILabel.subheadlineLabel(text: OWSLocalizedString(
            "DO_YOU_WANT_TO_USE_PROXY",
            comment: "Confirmation text displayed in a sheet presented when user taps on Signal Proxy link in chat.",
        ))

        let titleStack = UIStackView(arrangedSubviews: [imageView, titleLabel, questionLabel])
        titleStack.axis = .vertical
        titleStack.alignment = .fill
        titleStack.setCustomSpacing(16, after: imageView)
        titleStack.setCustomSpacing(4, after: titleLabel)
        stackView.addArrangedSubview(titleStack)

        // Address pill
        let proxyHost = url.fragment!
        let addressLabel = UILabel()
        addressLabel.text = proxyHost
        addressLabel.font = .dynamicTypeBody.monospaced()
        addressLabel.textColor = .Signal.secondaryLabel

        let addressLabelContainer = UIView()
        addressLabelContainer.directionalLayoutMargins = .init(hMargin: 20, vMargin: 15)
        addressLabelContainer.backgroundColor = .Signal.secondaryGroupedBackground
        if #available(iOS 26, *) {
            addressLabelContainer.cornerConfiguration = .capsule(maximumRadius: 26)
        } else {
            addressLabelContainer.layer.cornerRadius = 14
        }
        addressLabelContainer.addSubview(addressLabel)
        addressLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            addressLabel.topAnchor.constraint(equalTo: addressLabelContainer.layoutMarginsGuide.topAnchor),
            addressLabel.leadingAnchor.constraint(equalTo: addressLabelContainer.layoutMarginsGuide.leadingAnchor),
            addressLabel.trailingAnchor.constraint(equalTo: addressLabelContainer.layoutMarginsGuide.trailingAnchor),
            addressLabel.bottomAnchor.constraint(equalTo: addressLabelContainer.layoutMarginsGuide.bottomAnchor),
        ])
        stackView.addArrangedSubview(addressLabelContainer)

        // Buttons
        let useProxyButton = UIButton(
            configuration: .largePrimary(title: OWSLocalizedString(
                "USE_PROXY_BUTTON",
                comment: "Button to activate the signal proxy",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.useProxyTapped()
            },
        )
        let cancelButton = UIButton(
            configuration: .largeSecondary(title: CommonStrings.cancelButton),
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            },
        )
        let buttonStack = UIStackView(arrangedSubviews: [useProxyButton, cancelButton])
        buttonStack.axis = .vertical
        buttonStack.spacing = 12
        stackView.addArrangedSubview(buttonStack)
    }

    private func useProxyTapped() {
        let proxyHost = url.fragment!

        SSKEnvironment.shared.databaseStorageRef.write {
            SignalProxy.setProxyHost(host: proxyHost, useProxy: true, transaction: $0)
        }

        let presentingVC = presentingViewController
        _ = Task(priority: .userInitiated) {
            if await ProxyConnectionChecker(chatConnectionManager: DependenciesBridge.shared.chatConnectionManager).checkConnection() {
                presentingVC?.presentToast(text: OWSLocalizedString("PROXY_CONNECTED_SUCCESSFULLY", comment: "The provided proxy connected successfully"))
            } else {
                presentingVC?.presentToast(text: OWSLocalizedString("PROXY_FAILED_TO_CONNECT", comment: "The provided proxy couldn't connect"))
                SSKEnvironment.shared.databaseStorageRef.write { transaction in
                    SignalProxy.setProxyHost(host: proxyHost, useProxy: false, transaction: transaction)
                }
            }
        }

        dismiss(animated: true)
    }
}
