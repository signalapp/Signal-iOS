//
//  NamedView.swift
//  SwiftCSV
//
//  Created by Christian Tietze on 22/10/16.
//  Copyright © 2016 Naoto Kaneko. All rights reserved.
//

public struct NamedView: View {

    public var rows: [[String : String]]
    public var columns: [String : [String]]

    public init(header: [String], text: String, delimiter: Character, limitTo: Int? = nil, loadColumns: Bool = false) throws {

        var rows = [[String: String]]()
        var columns = [String: [String]]()

        try Parser.enumerateAsDict(header: header, content: text, delimiter: delimiter, limitTo: limitTo) { dict in
            rows.append(dict)
        }

        if loadColumns {
            for field in header {
                columns[field] = rows.map { $0[field] ?? "" }
            }
        }

        self.rows = rows
        self.columns = columns
    }
}
