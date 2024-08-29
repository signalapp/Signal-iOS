//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

struct LineByLineStringDiff {
    private let insertedLineGroups: [SequentialLineChanges]
    private let removedLineGroups: [SequentialLineChanges]

    private init(
        insertedLineGroups: [SequentialLineChanges],
        removedLineGroups: [SequentialLineChanges]
    ) {
        self.insertedLineGroups = insertedLineGroups
        self.removedLineGroups = removedLineGroups
    }

    static func diffing(lhs: String, rhs: String) -> LineByLineStringDiff {
        func lines(_ str: String) -> [String] {
            return str.split(whereSeparator: \.isNewline).map { String($0) }
        }

        let lhsLines = lines(lhs)
        let rhsLines = lines(rhs)
        let lineDiff = lhsLines.difference(from: rhsLines)

        let insertedLineGroups = Self.group(lineChanges: lineDiff.insertions)
        let removedLineGroups = Self.group(lineChanges: lineDiff.removals)

        return LineByLineStringDiff(
            insertedLineGroups: insertedLineGroups,
            removedLineGroups: removedLineGroups
        )
    }

    // MARK: -

    func prettyPrint(
        lhsLabel: String,
        rhsLabel: String,
        diffGroupDivider divider: String
    ) -> String {
        /// Sort the line change groups by the line number at which the group
        /// starts, in an attempt to improve the readability of a complex diff.
        let sortedLineChangeGroups = (insertedLineGroups + removedLineGroups)
            .sorted { lhsGroup, rhsGroup in
                return lhsGroup.sequenceStart < rhsGroup.sequenceStart
            }

        var output = "\(divider)\n"
        output.append(
            sortedLineChangeGroups.map { lineGroup in
                /// Because we took a diff of `lhs` from `rhs`, "insertions"
                /// will represent `lhs` lines that are missing from `rhs` and
                /// "removals" will represent `rhs` lines missing from `lhs`.
                return lineGroup.prettyPrint(
                    insertionLabel: lhsLabel,
                    removalLabel: rhsLabel
                )
            }.joined(separator: "\n\(divider)\n")
        )
        output.append("\n\(divider)")

        return output
    }
}

// MARK: - Groupings

private extension LineByLineStringDiff {
    /// Represents a single-line change in a larger multiline string diff.
    private typealias SingleLineChange = CollectionDifference<String>.Change

    /// Represents a non-empty group of sequential single-line changes.
    private struct SequentialLineChanges {
        private let sequentialLines: [SingleLineChange]

        /// The line number of the first in this sequence of line changes.
        var sequenceStart: Int {
            return sequentialLines.first!.offset
        }

        /// - Important
        /// The given group of sequential lines must not be empty!
        init(sequentialLines: [SingleLineChange]) {
            if sequentialLines.isEmpty {
                preconditionFailure("Grouped changes must not be empty!")
            }

            self.sequentialLines = sequentialLines
        }

        func prettyPrint(
            insertionLabel: String,
            removalLabel: String
        ) -> String {
            return sequentialLines.map { change -> String in
                return change.prettyPrint(
                    insertionLabel: insertionLabel,
                    removalLabel: removalLabel
                )
            }.joined(separator: "\n")
        }
    }

    /// Collates the given line changes into sequential groups.
    private static func group(lineChanges: [SingleLineChange]) -> [SequentialLineChanges] {
        var groupings = [SequentialLineChanges]()

        var currentGroup = [SingleLineChange]()
        for lineChange in lineChanges {
            if currentGroup.isEmpty {
                currentGroup.append(lineChange)
                continue
            }

            let lastElementInGroup = currentGroup.last!
            if lastElementInGroup.offset + 1 == lineChange.offset {
                currentGroup.append(lineChange)
            } else {
                groupings.append(SequentialLineChanges(sequentialLines: currentGroup))
                currentGroup = [lineChange]
            }
        }

        if !currentGroup.isEmpty {
            groupings.append(SequentialLineChanges(sequentialLines: currentGroup))
        }

        return groupings
    }
}

// MARK: -

private extension CollectionDifference.Change {
    var offset: Int {
        switch self {
        case
                .insert(let offset, _, _),
                .remove(let offset, _, _):
            return offset
        }
    }

    func prettyPrint(
        insertionLabel: String,
        removalLabel: String
    ) -> String {
        switch self {
        case .insert(let offset, let element, _):
            return "\(insertionLabel)@\(offset): \(element)"
        case .remove(let offset, let element, _):
            return "\(removalLabel)@\(offset): \(element)"
        }
    }
}
