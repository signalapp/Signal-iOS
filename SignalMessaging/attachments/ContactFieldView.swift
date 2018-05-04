//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

public class ContactFieldView: UIView {

    @available(*, unavailable, message: "use other constructor instead.")
    public required init?(coder aDecoder: NSCoder) {
        fatalError("Unimplemented")
    }

    public required init(rows: [UIView], hMargin: CGFloat) {
        super.init(frame: CGRect.zero)

        self.layoutMargins = .zero
        self.preservesSuperviewLayoutMargins = false

        addRows(rows: rows, hMargin: hMargin)
    }

    private func addRows(rows: [UIView], hMargin: CGFloat) {

        var lastRow: UIView?

        let addSpacerRow = {
            guard let prevRow = lastRow else {
                owsFail("\(self.logTag) missing last row")
                return
            }
            let row = UIView()
            row.backgroundColor = UIColor(rgbHex: 0xdedee1)
            self.addSubview(row)
            row.autoSetDimension(.height, toSize: 1)
            row.autoPinLeadingToSuperviewMargin(withInset: hMargin)
            row.autoPinTrailingToSuperviewMargin()
            row.autoPinEdge(.top, to: .bottom, of: prevRow, withOffset: 0)
            lastRow = row
        }

        let addRow: ((UIView) -> Void) = { (row) in
            if lastRow != nil {
                addSpacerRow()
            }
            self.addSubview(row)
            row.autoPinLeadingToSuperviewMargin(withInset: hMargin)
            row.autoPinTrailingToSuperviewMargin(withInset: hMargin)
            if let lastRow = lastRow {
                row.autoPinEdge(.top, to: .bottom, of: lastRow, withOffset: 0)
            } else {
                row.autoPinEdge(toSuperviewEdge: .top, withInset: 0)
            }
            lastRow = row
        }

        for row in rows {
            addRow(row)
        }

        lastRow?.autoPinEdge(toSuperviewEdge: .bottom, withInset: 0)
    }
}
