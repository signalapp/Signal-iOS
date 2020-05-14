//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

class DeviceTransferInitialViewController: DeviceTransferBaseViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let titleLabel = self.titleLabel(
            text: NSLocalizedString("DEVICE_TRANSFER_PROMPT_TITLE",
                                    comment: "The title on the acttion sheet prompting the user if they want to transfer their device.")
        )
        contentView.addArrangedSubview(titleLabel)

        contentView.addArrangedSubview(.spacer(withHeight: 12))

        let explanationLabel = self.explanationLabel(
            explanationText: NSLocalizedString("DEVICE_TRANSFER_PROMPT_EXPLANATION",
                                               comment: "The explanation on the action sheet prompting the user if they want to transfer their device.")
        )
        contentView.addArrangedSubview(explanationLabel)

        let topSpacer = UIView.vStretchingSpacer()
        contentView.addArrangedSubview(topSpacer)

        let iconView = UIImageView(image: #imageLiteral(resourceName: "transfer-icon"))
        iconView.contentMode = .scaleAspectFit
        iconView.autoSetDimension(.height, toSize: 110)
        contentView.addArrangedSubview(iconView)

        let bottomSpacer = UIView.vStretchingSpacer()
        contentView.addArrangedSubview(bottomSpacer)
        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)

        let nextButton = button(title: CommonStrings.nextButton, selector: #selector(didTapNext))
        contentView.addArrangedSubview(nextButton)
    }

    @objc
    func didTapNext() {
        let qrScanner = DeviceTransferQRScanningViewController()
        navigationController?.pushViewController(qrScanner, animated: true)
    }
}
