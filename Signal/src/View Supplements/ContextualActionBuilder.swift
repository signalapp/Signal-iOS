//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

enum ContextualActionBuilder {
    typealias Handler = (_ completion: @escaping (_ success: Bool) -> Void) -> Void

    static func makeContextualAction(
        style: UIContextualAction.Style,
        color: UIColor,
        imageName: String,
        title: String,
        handler: @escaping Handler,
    ) -> UIContextualAction {
        return makeContextualAction(
            style: style,
            color: color,
            image: UIImage(named: imageName),
            title: title,
            handler: handler,
        )
    }

    static func makeContextualAction(
        style: UIContextualAction.Style,
        color: UIColor,
        image: UIImage?,
        title: String,
        handler: @escaping Handler,
    ) -> UIContextualAction {
        // We want to always show a title with the icon. iOS 26 does this by
        // default, but previous iOS versions only does when the cell's
        // height > 91, so we generate an image with the text below it.
        if #available(iOS 26, *) {
            let action = UIContextualAction(
                style: style,
                title: title,
            ) { _, _, completion in
                handler(completion)
            }
            action.backgroundColor = color
            action.image = image
            return action
        } else {
            let action = UIContextualAction(
                style: style,
                title: nil,
            ) { _, _, completion in
                handler(completion)
            }
            action.accessibilityLabel = title
            action.backgroundColor = color
            action.image = image?.withTitle(
                title,
                font: .dynamicTypeFootnote.medium(),
                color: .white,
                maxTitleWidth: 68,
                minimumScaleFactor: CGFloat(8) / CGFloat(13),
                spacing: 4,
            )?.withRenderingMode(.alwaysTemplate)

            return action
        }
    }
}
