//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

class CallMemberChromeOverlayView: UIView, CallMemberComposableView {
    private let muteIndicatorImage = UIImageView()
    private var muteLeadingConstraint: NSLayoutConstraint?
    private var muteBottomConstraint: NSLayoutConstraint?
    private var muteHeightConstraint: NSLayoutConstraint?

    private var muteInsets: CGFloat {
        return width > 102 ? 9 : 4
    }

    private var muteHeight: CGFloat {
        return width > 200 && UIDevice.current.isIPad ? 20 : 16
    }

    init() {
        super.init(frame: .zero)
        muteIndicatorImage.isHidden = true
        muteIndicatorImage.setTemplateImageName("mic-slash-fill-28", tintColor: .ows_white)
        addSubview(muteIndicatorImage)
        muteIndicatorImage.autoMatch(.width, to: .height, of: muteIndicatorImage)
        createAndActivateMuteLayoutConstraints()
    }

    private func createAndActivateMuteLayoutConstraints() {
        let muteLeadingConstraint = muteIndicatorImage.autoPinEdge(toSuperviewEdge: .leading, withInset: muteInsets)
        let muteBottomConstraint = muteIndicatorImage.autoPinEdge(toSuperviewEdge: .bottom, withInset: muteInsets)
        let muteHeightConstraint = muteIndicatorImage.autoSetDimension(.height, toSize: muteHeight)
        NSLayoutConstraint.activate([
            muteLeadingConstraint,
            muteBottomConstraint,
            muteHeightConstraint
        ])
        self.muteLeadingConstraint = muteLeadingConstraint
        self.muteBottomConstraint = muteBottomConstraint
        self.muteHeightConstraint = muteHeightConstraint
    }

    func rotateForPhoneOrientation(_ rotationAngle: CGFloat) {
        /// TODO: Add support for rotating other elements too.
        self.muteIndicatorImage.transform = CGAffineTransform(rotationAngle: rotationAngle)
    }

    func configure(
        call: SignalCall,
        isFullScreen: Bool = false,
        memberType: CallMemberView.ConfigurationType
    ) {
        switch memberType {
        case .local:
            muteIndicatorImage.isHidden = !call.isOutgoingAudioMuted || isFullScreen
        case .remote(let remoteDeviceState, let context):
            muteIndicatorImage.isHidden = context == .speaker || remoteDeviceState.audioMuted != true || isFullScreen
        }
    }

    func updateDimensions() {
        let constraints = [
            muteLeadingConstraint,
            muteBottomConstraint,
            muteHeightConstraint
        ].compactMap { $0 }
        NSLayoutConstraint.deactivate(constraints)
        createAndActivateMuteLayoutConstraints()
    }

    func clearConfiguration() {
        muteIndicatorImage.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
