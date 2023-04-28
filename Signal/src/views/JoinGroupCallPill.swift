//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc(OWSJoinGroupCallPill)
class JoinGroupCallPill: UIControl {

    @objc
    public var buttonText: String? {
        get { return callLabel.text }
        set {
            callLabel.text = newValue

            // If the localized string is too long, just hide the label. 70pts was picked out of
            // thin air. We should tweak this as this text gets localized and only hide in extreme cases.
            callLabel.isHidden = (callLabel.intrinsicContentSize.width > 70)
        }
    }

    private let callImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.setTemplateImageName("video-solid-24", tintColor: .ows_white)
        imageView.isUserInteractionEnabled = false
        return imageView
    }()

    private let callLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.dynamicTypeSubheadlineClamped.semibold()
        label.isUserInteractionEnabled = false
        return label
    }()

    private let backgroundPill: PillView = {
        let pill = PillView()
        pill.backgroundColor = .ows_accentGreen
        pill.isUserInteractionEnabled = false
        return pill
    }()

    private let dimmingView: UIView = {
        let pill = PillView()
        pill.backgroundColor = .ows_blackAlpha20
        pill.isHidden = true
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
        contentStack.isUserInteractionEnabled = false

        addSubview(backgroundPill)
        addSubview(contentStack)
        addSubview(dimmingView)

        callImageView.autoSetDimensions(to: CGSize(square: 20))
        callImageView.setCompressionResistanceHigh()
        callLabel.setCompressionResistanceHigh()

        contentStack.autoPinLeading(toEdgeOf: backgroundPill, offset: 12)
        contentStack.autoPinTrailing(toEdgeOf: backgroundPill, offset: -12)
        contentStack.autoPinEdge(.top, to: .top, of: backgroundPill, withOffset: 4)
        contentStack.autoPinEdge(.bottom, to: .bottom, of: backgroundPill, withOffset: -4)

        backgroundPill.autoPinEdgesToSuperviewEdges()
        dimmingView.autoPinEdgesToSuperviewEdges()

        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: .ThemeDidChange, object: nil)
        applyStyle()
    }

    override var isHighlighted: Bool {
        didSet { applyStyle() }
    }

    override var isEnabled: Bool {
        didSet { applyStyle() }
    }

    @objc
    func themeDidChange() {
        applyStyle()
    }

    private func applyStyle() {
        let enabledColor: UIColor = Theme.isDarkThemeEnabled ? .ows_whiteAlpha90 : .ows_white
        callLabel.textColor = isEnabled ? enabledColor : .ows_whiteAlpha40
        callImageView.tintColor = isEnabled ? enabledColor : .ows_whiteAlpha40

        // When we're highlighted, we should unhide the dimming view to darken the pill
        dimmingView.isHidden = !isHighlighted
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
