//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Compute the name of the given column.
///
/// This extension lives in its own file because at the time of writing
/// something about this block causes Xcode to stutter while editing the file
/// containing it, which was super annoying when working on other code in the
/// same file. Weird.
public extension SDSCodableModel {
    static func columnName(_ column: Columns, fullyQualified: Bool = false) -> String {
        fullyQualified ? "\(databaseTableName).\(column.rawValue)" : column.rawValue
    }
}
