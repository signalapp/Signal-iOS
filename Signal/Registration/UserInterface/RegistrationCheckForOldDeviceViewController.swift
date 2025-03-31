//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalUI
import SignalServiceKit

protocol RegistrationCheckForOldDevicePresenter: AnyObject {
    func hasOldDevice(_ hasOldDevice: Bool)
}

class RegistrationCheckForOldDeviceViewController: InteractiveSheetViewController {
    let stackView = UIStackView()

    public override var canBeDismissed: Bool { false }

    public override var sheetBackgroundColor: UIColor { Theme.tableView2PresentedBackgroundColor }

    private weak var presenter: RegistrationCheckForOldDevicePresenter?
    init(presenter: RegistrationCheckForOldDevicePresenter) {
        self.presenter = presenter
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        minimizedHeight = 300
        super.allowsExpansion = false

        stackView.axis = .vertical
        stackView.layoutMargins = UIEdgeInsets(hMargin: 24, vMargin: 24)
        stackView.spacing = 22
        stackView.isLayoutMarginsRelativeArrangement = true
        contentView.addSubview(stackView)

        let titleLabel = UILabel()
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.dynamicTypeTitle2.semibold()
        titleLabel.text = OWSLocalizedString(
            "TRANSFER_COMPLETE_SHEET_TITLE",
            comment: "Title for bottom sheet shown when device transfer completes on the receiving device."
        )
        titleLabel.setCompressionResistanceHigh()
        stackView.addArrangedSubview(titleLabel)

        let subtitleLabel = UILabel()
        subtitleLabel.text = OWSLocalizedString(
            "TRANSFER_COMPLETE_SHEET_SUBTITLE",
            comment: "Subtitle for bottom sheet shown when device transfer completes on the receiving device."
        )
        subtitleLabel.textAlignment = .center
        subtitleLabel.font = .dynamicTypeBody
        subtitleLabel.numberOfLines = 0
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.setCompressionResistanceHigh()
        stackView.addArrangedSubview(subtitleLabel)

        let exitButton = UIButton()
        exitButton.backgroundColor = .ows_accentBlue
        exitButton.layer.cornerRadius = 8
        exitButton.ows_titleEdgeInsets = UIEdgeInsets(hMargin: 0, vMargin: 18)
        exitButton.setTitleColor(.ows_white, for: .normal)
        exitButton.setTitle(
            "I have my old phone",
            for: .normal
        )
        exitButton.addTarget(self, action: #selector(didTapExitButton), for: .touchUpInside)
        exitButton.setCompressionResistanceHigh()
        stackView.addArrangedSubview(exitButton)

        let exitButton2 = UIButton()
        exitButton2.backgroundColor = .ows_accentBlue
        exitButton2.layer.cornerRadius = 8
        exitButton2.ows_titleEdgeInsets = UIEdgeInsets(hMargin: 0, vMargin: 18)
        exitButton2.setTitleColor(.ows_white, for: .normal)
        exitButton2.setTitle(
            "I don't have my old phone",
            for: .normal
        )
        exitButton2.addTarget(self, action: #selector(didTapExitButton2), for: .touchUpInside)
        exitButton2.setCompressionResistanceHigh()
        stackView.addArrangedSubview(exitButton2)

        stackView.autoPinEdge(.top, to: .top, of: contentView)
        stackView.autoPinWidth(toWidthOf: contentView)
    }

    @objc
    private func didTapExitButton() {
        presenter?.hasOldDevice(true)
    }

    @objc
    private func didTapExitButton2() {
        presenter?.hasOldDevice(false)
    }
}
