//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit

public class ActionSheetContentBuilder {

    var subviews = [UIView]()

    func buildLabel(text: String? = nil,
                    textColor: UIColor? = nil,
                    font: UIFont? = nil,
                    textAlignment: NSTextAlignment = .natural) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = textColor ?? Theme.primaryTextColor
        label.font = font ?? UIFont.ows_dynamicTypeBody
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.textAlignment = textAlignment
        return label
    }

    func buildTitleLabel(text: String) -> UILabel {
        buildLabel(text: text,
                   font: UIFont.ows_dynamicTypeTitle2.ows_semibold,
                   textAlignment: .center)
    }

    func add(_ subview: UIView) {
        subviews.append(subview)
    }

    func addVerticalSpacer(height: CGFloat) {
        add(UIView.spacer(withHeight: height))
    }

    func addBottomButton(
        title: String,
        titleColor: UIColor,
        backgroundColor: UIColor,
        target: Any,
        selector: Selector
    ) {
        let buttonFont = UIFont.ows_dynamicTypeBodyClamped.ows_semibold
        let buttonHeight = OWSFlatButton.heightForFont(buttonFont)
        let upgradeButton = OWSFlatButton.button(title: title,
                                                 font: buttonFont,
                                                 titleColor: titleColor,
                                                 backgroundColor: backgroundColor,
                                                 target: target,
                                                 selector: selector)
        upgradeButton.autoSetDimension(.height, toSize: buttonHeight)
        subviews.append(upgradeButton)
    }
}
