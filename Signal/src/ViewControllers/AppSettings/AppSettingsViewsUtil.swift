//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

public class AppSettingsViewsUtil {
    public class func newCell(cellOuterInsets: UIEdgeInsets) -> UITableViewCell {
        let cell = OWSTableItem.newCell()
        cell.selectionStyle = .none
        cell.layoutMargins = cellOuterInsets
        cell.contentView.layoutMargins = .zero
        return cell
    }

    public class func loadingTableItem(cellOuterInsets: UIEdgeInsets) -> OWSTableItem {
        OWSTableItem.init(
            customCellBlock: {
                let cell = newCell(cellOuterInsets: cellOuterInsets)

                let stackView = UIStackView()
                stackView.axis = .vertical
                stackView.alignment = .center
                stackView.layoutMargins = UIEdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0)
                stackView.isLayoutMarginsRelativeArrangement = true
                cell.contentView.addSubview(stackView)
                stackView.autoPinEdgesToSuperviewEdges()

                let activitySpinner: UIActivityIndicatorView
                if #available(iOS 13, *) {
                    activitySpinner = UIActivityIndicatorView(style: .medium)
                } else {
                    activitySpinner = UIActivityIndicatorView(style: .gray)
                }

                activitySpinner.startAnimating()

                stackView.addArrangedSubview(activitySpinner)

                return cell
            },
            actionBlock: {}
        )
    }
}
