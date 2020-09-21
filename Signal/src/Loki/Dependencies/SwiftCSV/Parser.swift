//
//  Parser.swift
//  SwiftCSV
//
//  Created by Will Richardson on 13/04/16.
//  Copyright © 2016 Naoto Kaneko. All rights reserved.
//

extension CSV {
    /// Parse the file and call a block on each row, passing it in as a list of fields
    /// limitTo will limit the result to a certain number of lines
    public func enumerateAsArray(limitTo: Int? = nil, startAt: Int = 0, _ block: @escaping ([String]) -> ()) throws {

        try Parser.enumerateAsArray(text: self.text, delimiter: self.delimiter, limitTo: limitTo, startAt: startAt, block: block)
    }

    public func enumerateAsDict(_ block: @escaping ([String : String]) -> ()) throws {

        try Parser.enumerateAsDict(header: self.header, content: self.text, delimiter: self.delimiter, block: block)
    }
}

enum Parser {

    static func array(text: String, delimiter: Character, limitTo: Int? = nil, startAt: Int = 0) throws -> [[String]] {

        var rows = [[String]]()

        try enumerateAsArray(text: text, delimiter: delimiter) { row in
            rows.append(row)
        }

        return rows
    }

    /// Parse the text and call a block on each row, passing it in as a list of fields.
    ///
    /// - parameter text: Text to parse.
    /// - parameter delimiter: Character to split row and header fields by (default is ',')
    /// - parameter limitTo: If set to non-nil value, enumeration stops 
    ///   at the row with index `limitTo` (or on end-of-text, whichever is earlier.
    /// - parameter startAt: Offset of rows to ignore before invoking `block` for the first time. Default is 0.
    /// - parameter block: Callback invoked for every parsed row between `startAt` and `limitTo` in `text`.
    static func enumerateAsArray(text: String, delimiter: Character, limitTo: Int? = nil, startAt: Int = 0, block: @escaping ([String]) -> ()) throws {
        var currentIndex = text.startIndex
        let endIndex = text.endIndex

        var fields = [String]()
        var field = ""

        var count = 0

        func finishRow() {
            fields.append(String(field))
            if count >= startAt {
                block(fields)
            }
            count += 1
            fields = [String]()
            field = ""
        }

        var state: ParsingState = ParsingState(
            delimiter: delimiter,
            finishRow: finishRow,
            appendChar: { field.append($0) },
            finishField: {
                fields.append(field)
                field = ""
        })

        func limitReached(_ count: Int) -> Bool {

            guard let limitTo = limitTo,
                count >= limitTo
                else { return false }

            return true
        }

        while currentIndex < endIndex {
            let char = text[currentIndex]

            try state.change(char)

            if limitReached(count) {
                break
            }

            currentIndex = text.index(after: currentIndex)
        }

        if !fields.isEmpty || !field.isEmpty || limitReached(count) {
            fields.append(field)
            block(fields)
        }
    }

    static func enumerateAsDict(header: [String], content: String, delimiter: Character, limitTo: Int? = nil, block: @escaping ([String : String]) -> ()) throws {

        let enumeratedHeader = header.enumerated()

        try enumerateAsArray(text: content, delimiter: delimiter, startAt: 1) { fields in
            var dict = [String: String]()
            for (index, head) in enumeratedHeader {
                dict[head] = index < fields.count ? fields[index] : ""
            }
            block(dict)
        }
    }
}
