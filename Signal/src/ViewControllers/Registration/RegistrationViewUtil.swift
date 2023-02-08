//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalUI

// MARK: - Layout margins

extension UIEdgeInsets {
    static func layoutMarginsForRegistration(
        _ horizontalSizeClass: UIUserInterfaceSizeClass
    ) -> UIEdgeInsets {
        switch horizontalSizeClass {
        case .unspecified, .compact:
            return UIEdgeInsets(margin: 32)
        case .regular:
            return UIEdgeInsets(margin: 112)
        @unknown default:
            return UIEdgeInsets(margin: 32)
        }
    }
}

// MARK: - Labels

extension UILabel {
    static func titleLabelForRegistration(text: String) -> UILabel {
        let result = UILabel()
        result.text = text
        result.textColor = Theme.primaryTextColor
        result.font = UIFont.ows_dynamicTypeTitle1Clamped.ows_semibold
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        result.textAlignment = .center
        return result
    }
}

// MARK: - Buttons

extension OWSFlatButton {
    static func primaryButtonForRegistration(title: String, target: Any, selector: Selector) -> OWSFlatButton {
        let result = insetButton(
            title: title,
            font: UIFont.ows_dynamicTypeBodyClamped.ows_semibold,
            titleColor: .white,
            backgroundColor: .ows_accentBlue,
            target: target,
            selector: selector
        )
        result.contentEdgeInsets = UIEdgeInsets(hMargin: 4, vMargin: 14)
        return result
    }
}
