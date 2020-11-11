//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSJoinGroupCallPill)
class JoinGroupCallPill: UIControl {

    private let callImageView: UIImageView = {
        let callImage = UIImage(named: "video-solid-24")?
            .withRenderingMode(.alwaysTemplate)
        let imageView = UIImageView(image: callImage)
        imageView.tintColor = .ows_white
        imageView.isUserInteractionEnabled = false
        return imageView
    }()

    private let callLabel: UILabel = {
        let label = UILabel()
        label.text = NSLocalizedString("JOIN_CALL_PILL_BUTTON", comment: "Button to join an active group call")
        label.font = UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold
        label.textColor = .ows_white
        label.isUserInteractionEnabled = false
        return label
    }()

    private let backgroundPill: PillView = {
        let pill = PillView()
        pill.backgroundColor = .ows_accentGreen
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.isUserInteractionEnabled = false
        return pill
    }()

    init() {
        super.init(frame: .zero)
        let contentStack = UIStackView(arrangedSubviews: [
            callImageView,
            callLabel
        ])
        contentStack.axis = .horizontal
        contentStack.spacing = 4
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.isUserInteractionEnabled = false

        addSubview(backgroundPill)
        addSubview(contentStack)

        backgroundPill.autoPinWidthToSuperview()
        backgroundPill.autoSetDimension(.height, toSize: 28)
        backgroundPill.autoVCenterInSuperview()
        contentStack.autoPinEdgesToSuperviewMargins()
        callImageView.autoSetDimensions(to: CGSize(square: 20))
    }

    override var isEnabled: Bool {
        didSet {
//            TODO: Check with design about. Should the color be muted when disabled?
//            backgroundPill.backgroundColor = isEnabled ? .ows_accentGreen : .ows_accentRed
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
