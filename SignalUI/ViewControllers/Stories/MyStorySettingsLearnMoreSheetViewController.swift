//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

public class MyStorySettingsLearnMoreSheetViewController: InteractiveSheetViewController {

    private var intrinsicSizeObservation: NSKeyValueObservation?

    public required init() {
        super.init()

        scrollView.bounces = false
        scrollView.isScrollEnabled = false

        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 12

        stackView.addArrangedSubview(connectionsImageView)
        stackView.setCustomSpacing(24, after: connectionsImageView)
        stackView.addArrangedSubview(header)
        stackView.setCustomSpacing(20, after: header)
        let bulletPoints = bulletPoints
        stackView.addArrangedSubviews(bulletPoints)
        stackView.setCustomSpacing(20, after: bulletPoints.last!)
        stackView.addArrangedSubview(footer)

        let insets = UIEdgeInsets(top: 20, left: 24, bottom: 80, right: 24)
        contentView.addSubview(scrollView)
        scrollView.autoPinEdgesToSuperviewEdges()
        scrollView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges(with: insets)
        stackView.autoConstrainAttribute(.width, to: .width, of: contentView, withOffset: -insets.totalWidth)

        self.allowsExpansion = false
        intrinsicSizeObservation = stackView.observe(\.bounds, changeHandler: { [weak self] stackView, _ in
            self?.minimizedHeight = stackView.bounds.height + insets.totalHeight
            self?.scrollView.isScrollEnabled = (self?.maxHeight ?? 0) < stackView.bounds.height
        })
    }

    override public func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        scrollView.isScrollEnabled = self.maxHeight < stackView.bounds.height
    }

    let scrollView = UIScrollView()
    let stackView = UIStackView()

    let connectionsImageView: UIImageView = {
        let view = UIImageView()
        view.image = UIImage(named: "signal_connections")
        view.tintColor = .ows_accentBlue
        view.contentMode = .scaleAspectFit
        view.autoSetDimension(.height, toSize: 88)
        return view
    }()

    let header: UILabel = {
        let label = UILabel()
        label.attributedText = OWSLocalizedString(
            "STORY_SETTINGS_LEARN_MORE_SHEET_HEADER_FORMAT",
            comment: "Header for the explainer sheet for signal connections"
        ).styled(
            with: .font(.dynamicTypeBodyClamped),
            .xmlRules([.style("bold", .init(.font(UIFont.dynamicTypeBodyClamped.semibold())))])
        )
        label.textColor = Theme.primaryTextColor
        label.numberOfLines = 0
        label.setCompressionResistanceHigh()
        return label
    }()

    let bulletPoints: [UIView] = {
        return [
            OWSLocalizedString(
                "STORY_SETTINGS_LEARN_MORE_SHEET_BULLET_1",
                comment: "First bullet point for the explainer sheet for signal connections"
            ),
            OWSLocalizedString(
                "STORY_SETTINGS_LEARN_MORE_SHEET_BULLET_2",
                comment: "Second bullet point for the explainer sheet for signal connections"
            ),
            OWSLocalizedString(
                "STORY_SETTINGS_LEARN_MORE_SHEET_BULLET_3",
                comment: "Third bullet point for the explainer sheet for signal connections"
            )
        ].map { text in
            return ListPointView(text: text)
        }
    }()

    let footer: UILabel = {
        let label = UILabel()
        label.text = OWSLocalizedString(
            "STORY_SETTINGS_LEARN_MORE_SHEET_FOOTER",
            comment: "Footer for the explainer sheet for signal connections"
        )
        label.textColor = Theme.primaryTextColor
        label.font = .dynamicTypeBodyClamped
        label.numberOfLines = 0
        label.setCompressionResistanceHigh()
        return label
    }()

    private class ListPointView: UIStackView {

        init(text: String) {
            super.init(frame: .zero)

            self.axis = .horizontal
            self.alignment = .center
            self.spacing = 8

            let label = UILabel()
            label.text = text
            label.numberOfLines = 0
            label.textColor = Theme.primaryTextColor
            label.font = .dynamicTypeBodyClamped

            let bulletPoint = UIView()
            bulletPoint.backgroundColor = UIColor(rgbHex: 0xC4C4C4)

            addArrangedSubview(.spacer(withWidth: 4))
            addArrangedSubview(bulletPoint)
            addArrangedSubview(label)

            bulletPoint.autoSetDimensions(to: .init(width: 4, height: 14))
            label.setCompressionResistanceHigh()
        }

        required init(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
