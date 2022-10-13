//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import CoreMIDI

struct Explain: CustomStringConvertible {
    let entries: [ExplainEntry]
    private init(entries: [ExplainEntry]) {
        self.entries = entries
    }

    static func query(
        _ db: Database,
        sql: String,
        arguments: StatementArguments = StatementArguments()
    ) throws -> Explain {
        let entries = try ExplainEntry.fetchAll(db, sql: "EXPLAIN " + sql, arguments: arguments)
        return Explain(entries: entries)
    }

    var description: String {
        let maxAddr     = entries.map { $0.addr.count }.max() ?? 0
        let maxOpcode   = entries.map { $0.opcode.count }.max() ?? 0
        let maxP1       = entries.map { $0.p1.count }.max() ?? 0
        let maxP2       = entries.map { $0.p2.count }.max() ?? 0
        let maxP3       = entries.map { $0.p3.count }.max() ?? 0
        let maxP4       = entries.map { $0.p4.count }.max() ?? 0
        let maxP5       = entries.map { $0.p5.count }.max() ?? 0

        let addrHeader = "addr"
        let opcodeHeader = "opcode"
        let p1Header = "p1"
        let p2Header = "p2"
        let p3Header = "p3"
        let p4Header = "p4"
        let p5Header = "p5"
        let commentHeader = "comment"

        let columnWidths = [
            maxAddr.clamp(addrHeader.count, 10),
            maxOpcode.clamp(opcodeHeader.count, 20),
            maxP1.clamp(p1Header.count, 20),
            maxP2.clamp(p2Header.count, 20),
            maxP3.clamp(p3Header.count, 20),
            maxP4.clamp(p4Header.count, 20),
            maxP5.clamp(p5Header.count, 20),
            commentHeader.count + 4
        ]

        let buildRow: ([String], Character) -> String = { args, pad in
            args.enumerated().map { idx, string in
                if let minWidth = columnWidths[safe: idx] {
                    return string + String(Array(repeating: pad, count: minWidth - string.count))
                } else {
                    return string
                }
            }.joined(separator: " ")
        }

        let infoMessage: String
        if entries.compactMap({ $0.comment }).isEmpty {
            infoMessage = "Note: Comments not available. Consider recompiling SQLite with -DSQLITE_ENABLE_EXPLAIN_COMMENTS. See Explain.swift for more info."
        } else {
            infoMessage = ""
        }

        let rowStrings = [
            infoMessage,
            buildRow([addrHeader, opcodeHeader, p1Header, p2Header, p3Header, p4Header, p5Header, commentHeader], " "),
            buildRow(["", "", "", "", "", "", "", ""], "-")
        ] + entries.map { entry in
            buildRow([entry.addr, entry.opcode, entry.p1, entry.p2, entry.p3, entry.p4, entry.p5, entry.comment ?? ""], " ")
        }

        return rowStrings.joined(separator: "\n")
    }
}

struct ExplainEntry: Decodable, FetchableRecord {
    let addr: String
    let opcode: String
    let p1: String
    let p2: String
    let p3: String
    let p4: String
    let p5: String

    // From: https://www.sqlite.org/opcode.html#viewing_the_bytecode
    // > the "comment" column in the EXPLAIN output is only provided if SQLite is compiled with
    // > the -DSQLITE_ENABLE_EXPLAIN_COMMENTS options
    // This can definitely be useful when trying to figure out which indices a query might be using
    let comment: String?
}
