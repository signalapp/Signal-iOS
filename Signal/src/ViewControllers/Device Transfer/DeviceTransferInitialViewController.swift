//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Lottie
import SignalMessaging

class DeviceTransferInitialViewController: DeviceTransferBaseViewController {
    let animationView = AnimationView(name: "transfer")

    override func viewDidLoad() {
        super.viewDidLoad()

        let titleLabel = self.titleLabel(
            text: OWSLocalizedString("DEVICE_TRANSFER_PROMPT_TITLE",
                                    comment: "The title on the acttion sheet prompting the user if they want to transfer their device.")
        )
        contentView.addArrangedSubview(titleLabel)

        contentView.addArrangedSubview(.spacer(withHeight: 12))

        let explanationLabel = self.explanationLabel(
            explanationText: OWSLocalizedString("DEVICE_TRANSFER_PROMPT_EXPLANATION",
                                               comment: "The explanation on the action sheet prompting the user if they want to transfer their device.")
        )
        contentView.addArrangedSubview(explanationLabel)

        let topSpacer = UIView.vStretchingSpacer()
        contentView.addArrangedSubview(topSpacer)

        animationView.contentMode = .scaleAspectFit
        animationView.loopMode = .loop
        animationView.backgroundBehavior = .pauseAndRestore
        animationView.autoSetDimension(.height, toSize: 110)
        contentView.addArrangedSubview(animationView)

        let bottomSpacer = UIView.vStretchingSpacer()
        contentView.addArrangedSubview(bottomSpacer)
        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)

        let nextButton = button(title: CommonStrings.nextButton, selector: #selector(didTapNext))
        contentView.addArrangedSubview(nextButton)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        animationView.play()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        animationView.stop()
    }

    @objc
    private func didTapNext() {
        ows_askForCameraPermissions { granted in
            guard granted else { return }
            let qrScanner = DeviceTransferQRScanningViewController()
            self.navigationController?.pushViewController(qrScanner, animated: true)
        }
    }
}
