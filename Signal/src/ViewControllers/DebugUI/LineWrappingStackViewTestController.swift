//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if USE_DEBUG_UI

import Foundation
import SignalUI
public import UIKit

public class LineWrappingStackViewTestController: UIViewController {

    override public func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .white

        let numLabelsLabel = UILabel()
        numLabelsLabel.textAlignment = .center
        numLabelsLabel.text = "# of labels"
        let numLinesLabel = UILabel()
        numLinesLabel.textAlignment = .center
        numLinesLabel.text = "# of lines per label"
        let numCharactersLabel = UILabel()
        numCharactersLabel.textAlignment = .center
        numCharactersLabel.adjustsFontSizeToFitWidth = true
        numCharactersLabel.text = "# of characters per label"
        let labelWidthConstraintLabel = UILabel()
        labelWidthConstraintLabel.textAlignment = .center
        labelWidthConstraintLabel.adjustsFontSizeToFitWidth = true
        labelWidthConstraintLabel.text = "Constrained label width"
        let leadingIconLabel = UILabel()
        leadingIconLabel.textAlignment = .center
        leadingIconLabel.adjustsFontSizeToFitWidth = true
        leadingIconLabel.text = "Show leading icon"
        let trailingIconLabel = UILabel()
        trailingIconLabel.textAlignment = .center
        trailingIconLabel.adjustsFontSizeToFitWidth = true
        trailingIconLabel.text = "Show trailing icon"
        let overflowLeadingIconLabel = UILabel()
        overflowLeadingIconLabel.textAlignment = .center
        overflowLeadingIconLabel.adjustsFontSizeToFitWidth = true
        overflowLeadingIconLabel.text = "Overflow leading icon"
        let overflowTrailingIconLabel = UILabel()
        overflowTrailingIconLabel.textAlignment = .center
        overflowTrailingIconLabel.adjustsFontSizeToFitWidth = true
        overflowTrailingIconLabel.text = "Overflow trailing icon"

        let slidersStack = UIStackView()
        slidersStack.axis = .vertical
        slidersStack.spacing = 12
        slidersStack.alignment = .fill
        slidersStack.distribution = .equalSpacing

        for (hViews, distribution) in [
            ([numLabelsLabel, numLinesLabel], UIStackView.Distribution.fillEqually),
            ([numLabelsSlider, numLinesSlider], UIStackView.Distribution.fillEqually),
            ([numCharactersLabel, labelWidthConstraintLabel], UIStackView.Distribution.fillEqually),
            ([numCharactersSlider, labelWidthConstraintSlider], UIStackView.Distribution.fillEqually),
            ([leadingIconLabel, trailingIconLabel], UIStackView.Distribution.fillEqually),
            ([showLeadingIconSwitch, showTrailingIconSwitch], UIStackView.Distribution.equalCentering),
            ([overflowLeadingIconLabel, overflowTrailingIconLabel], UIStackView.Distribution.fillEqually),
            ([overflowLeadingIconSwitch, overflowTrailingIconSwitch], UIStackView.Distribution.equalCentering),
        ] {
            slidersStack.addArrangedSubview({
                let hStack = UIStackView()
                hStack.axis = .horizontal
                hStack.spacing = 12
                hStack.alignment = .center
                hStack.distribution = distribution
                hViews.forEach { hStack.addArrangedSubview($0) }
                return hStack
            }())
        }

        view.addSubview(slidersStack)
        view.addSubview(outerStackView)

        slidersStack.autoPinEdge(toSuperviewEdge: .left, withInset: 12)
        slidersStack.autoPinEdge(toSuperviewEdge: .right, withInset: 12)
        slidersStack.autoPinEdge(toSuperviewEdge: .top, withInset: 20)

        outerStackView.axis = .horizontal
        outerStackView.distribution = .fill
        outerStackView.spacing = 8
        outerStackView.alignment = .fill

        outerStackView.autoPinEdge(.left, to: .left, of: view, withOffset: 12)
        outerStackView.autoPinEdge(.right, to: .right, of: view, withOffset: -12)
        outerStackView.autoPinEdge(.top, to: .bottom, of: slidersStack, withOffset: 20)

        outerStackView.addArrangedSubview(overflowStackView)
        overflowStackView.layer.borderWidth = 1
        overflowStackView.layer.borderColor = UIColor.blue.cgColor
        overflowStackView.addArrangedSubview(leadingIcon)
        overflowStackView.addArrangedSubview(trailingIcon)

        render()
    }

    static let loremIpsum = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Donec ante augue, dapibus quis pretium nec, tincidunt ac odio. Vestibulum ullamcorper efficitur nibh, eget mollis sem blandit eget. Orci varius natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Nulla ac mattis dolor, quis tempor orci. Donec quis augue rhoncus, viverra odio quis, tincidunt quam. Sed varius purus sit amet suscipit tincidunt. Integer eu lectus in odio euismod consequat."

    private lazy var outerStackView = UIStackView()
    private lazy var overflowStackView = LineWrappingStackView()

    private var numLabels = 1
    private var numLines = 1
    private var numCharacters = 10
    private lazy var labelWidthConstraint = view.bounds.width - 24
    private var labelWidthConstraints = [NSLayoutConstraint]()

    private var labels = [UILabel]()

    private lazy var leadingIcon: UIImageView = {
        let imageView = UIImageView(image: .init(named: "person-circle"))
        imageView.contentMode = .scaleAspectFit
        imageView.autoSetDimensions(to: .square(24))
        imageView.isHidden = true
        return imageView
    }()

    private lazy var trailingIcon: UIImageView = {
        let imageView = UIImageView(image: .init(named: "x-bold"))
        imageView.contentMode = .scaleAspectFit
        imageView.autoSetDimensions(to: .square(24))
        imageView.isHidden = true
        return imageView
    }()

    func render() {
        while labels.count > numLabels {
            labels.popLast().map { overflowStackView.removeArrangedSubview($0) }
            _ = labelWidthConstraints.popLast()
        }
        while labels.count < numLabels {
            let label = UILabel()
            label.layer.borderWidth = 1
            label.layer.borderColor = UIColor.red.cgColor
            overflowStackView.addArrangedSubview(label, atIndex: overflowStackView.arrangedSubviews.count - 1)
            labels.append(label)
            let constraint = label.widthAnchor.constraint(lessThanOrEqualToConstant: labelWidthConstraint)
            constraint.isActive = true
            constraint.priority = .required
            labelWidthConstraints.append(constraint)
        }

        let text = String(Self.loremIpsum.prefix(numCharacters))

        labels.forEach {
            $0.numberOfLines = numLines
            $0.text = text
        }
        labelWidthConstraints.forEach({
            $0.constant = labelWidthConstraint
            if labelWidthConstraint >= view.bounds.width - 24 {
                $0.isActive = false
            } else {
                $0.isActive = true
            }
        })
        overflowStackView.invalidateIntrinsicContentSize()
        overflowStackView.setNeedsLayout()
    }

    private lazy var numLabelsSlider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = 1
        slider.maximumValue = 5
        slider.value = 1
        slider.addTarget(self, action: #selector(didChangeNumLabels), for: .valueChanged)
        return slider
    }()

    @objc
    private func didChangeNumLabels() {
        numLabels = Int(round(numLabelsSlider.value))
        render()
    }

    private lazy var numLinesSlider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = 5
        slider.value = 1
        slider.addTarget(self, action: #selector(didChangeNumLines), for: .valueChanged)
        return slider
    }()

    @objc
    private func didChangeNumLines() {
        numLines = Int(round(numLinesSlider.value))
        render()
    }

    private lazy var numCharactersSlider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = 1
        slider.maximumValue = Float(Self.loremIpsum.count)
        slider.value = 10
        slider.addTarget(self, action: #selector(didChangeNumCharacters), for: .valueChanged)
        return slider
    }()

    @objc
    private func didChangeNumCharacters() {
        numCharacters = Int(round(numCharactersSlider.value))
        render()
    }

    private lazy var labelWidthConstraintSlider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = Float(view.bounds.width - 24)
        slider.value = Float(view.bounds.width - 24)
        slider.addTarget(self, action: #selector(didChangeLabelWidthConstraint), for: .valueChanged)
        return slider
    }()

    @objc
    private func didChangeLabelWidthConstraint() {
        labelWidthConstraint = CGFloat(labelWidthConstraintSlider.value)
        render()
    }

    private lazy var showLeadingIconSwitch: UISwitch = {
        let switchView = UISwitch()
        switchView.isOn = false
        switchView.addTarget(self, action: #selector(didChangeLeadingIconHidden), for: .valueChanged)
        return switchView
    }()

    @objc
    private func didChangeLeadingIconHidden() {
        leadingIcon.isHidden = !showLeadingIconSwitch.isOn
        render()
    }

    private lazy var showTrailingIconSwitch: UISwitch = {
        let switchView = UISwitch()
        switchView.isOn = false
        switchView.addTarget(self, action: #selector(didChangeTrailingIconHidden), for: .valueChanged)
        return switchView
    }()

    @objc
    private func didChangeTrailingIconHidden() {
        trailingIcon.isHidden = !showTrailingIconSwitch.isOn
        render()
    }

    private lazy var overflowLeadingIconSwitch: UISwitch = {
        let switchView = UISwitch()
        switchView.isOn = true
        switchView.addTarget(self, action: #selector(didChangeLeadingIconOverflow), for: .valueChanged)
        return switchView
    }()

    @objc
    private func didChangeLeadingIconOverflow() {
        if overflowLeadingIconSwitch.isOn {
            outerStackView.removeArrangedSubview(leadingIcon)
            overflowStackView.addArrangedSubview(leadingIcon, atIndex: 0)
        } else {
            overflowStackView.removeArrangedSubview(leadingIcon)
            outerStackView.insertArrangedSubview(leadingIcon, at: 0)
        }
        render()
    }

    private lazy var overflowTrailingIconSwitch: UISwitch = {
        let switchView = UISwitch()
        switchView.isOn = true
        switchView.addTarget(self, action: #selector(didChangeTrailingIconOverflow), for: .valueChanged)
        return switchView
    }()

    @objc
    private func didChangeTrailingIconOverflow() {
        if overflowTrailingIconSwitch.isOn {
            outerStackView.removeArrangedSubview(trailingIcon)
            overflowStackView.addArrangedSubview(trailingIcon)
        } else {
            overflowStackView.removeArrangedSubview(trailingIcon)
            outerStackView.addArrangedSubview(trailingIcon)
        }
        render()
    }
}

#endif
