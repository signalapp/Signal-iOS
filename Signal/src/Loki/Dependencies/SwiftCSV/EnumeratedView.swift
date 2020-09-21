//
//  EnumeratedView.swift
//  SwiftCSV
//
//  Created by Christian Tietze on 25/10/16.
//  Copyright © 2016 Naoto Kaneko. All rights reserved.
//

import Foundation

public struct EnumeratedView: View {

    public struct Column {
        public let header: String
        public let rows: [String]
    }

    public private(set) var rows: [[String]]
    public private(set) var columns: [Column]

    public init(header: [String], text: String, delimiter: Character, limitTo: Int? = nil, loadColumns: Bool = false) throws {

        var rows = [[String]]()
        var columns: [EnumeratedView.Column] = []

        try Parser.enumerateAsArray(text: text, delimiter: delimiter, limitTo: limitTo, startAt: 1) { fields in
            rows.append(fields)
        }

        if loadColumns {
            columns = header.enumerated().map { (index: Int, header: String) -> EnumeratedView.Column in

                return EnumeratedView.Column(
                    header: header,
                    rows: rows.map { $0[index] })
            }
        }

        self.rows = rows
        self.columns = columns
    }

}
