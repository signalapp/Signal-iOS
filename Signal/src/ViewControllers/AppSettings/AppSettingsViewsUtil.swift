//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalUI
import UIKit

public class AppSettingsViewsUtil {
    public class func newCell() -> UITableViewCell {
        let cell = OWSTableItem.newCell()
        cell.selectionStyle = .none
        return cell
    }

    public class func loadingTableItem() -> OWSTableItem {
        OWSTableItem(
            customCellBlock: {
                let cell = newCell()

                let stackView = UIStackView()
                stackView.axis = .vertical
                stackView.alignment = .center
                stackView.layoutMargins = UIEdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0)
                stackView.isLayoutMarginsRelativeArrangement = true
                cell.contentView.addSubview(stackView)
                stackView.autoPinEdgesToSuperviewEdges()

                let activitySpinner = UIActivityIndicatorView(style: .medium)
                activitySpinner.startAnimating()

                stackView.addArrangedSubview(activitySpinner)

                return cell
            },
            actionBlock: {},
        )
    }
}
