//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

struct Genstrings {
    enum DecodingError: Error {
        case nonStringKeys
    }

    /// Filters a .stringsdict file based on genstrings output.
    ///
    /// The `genstrings` command can find NSLocalizedString/OWSLocalizedString
    /// references within the codebase, but it always produces a .strings file.
    /// Despite this, it's useful for auto-genstrings to remove strings that are
    /// no longer referenced. This attempts to bridge that gap by filtering a
    /// .stringsdict file based on the keys from a .strings file.
    ///
    /// - Parameters:
    ///   - resourceFile: A `ResourceFile` that refers to a .stringsdict file.
    ///   - repositoryURL: The URL of the repository containing `resourceFile`.
    ///   - temporaryDirectoryURL:
    ///       A temporary URL to a directory where a `genstrings`-produced
    ///       `.strings` file is located. The `.strings` file should have the
    ///       same base name as `resourceFile`.
    static func filterPluralAware(
        resourceFile: ResourceFile,
        repositoryURL: URL,
        temporaryDirectoryURL: URL
    ) throws {
        precondition(resourceFile.filename.hasSuffix(".stringsdict"))

        // The URL where the .stringsdict is stored in the repository.
        let stringsDictURL = repositoryURL.appendingPathComponent(resourceFile.relativeSourcePath)

        // The URL where a .strings file was generated with keys that *should* exist.
        let generatedStringsURL = temporaryDirectoryURL.appendingPathComponent(resourceFile.filename)
            .deletingPathExtension().appendingPathExtension("strings")

        let existingValues = try loadExistingValues(at: stringsDictURL)
        let expectedKeys = try loadExpectedKeys(at: generatedStringsURL)
        // Remove any values that genstrings didn't discover
        let filteredValues = existingValues.filter { expectedKeys.contains($0.key) }
        // If there are any changes, write the new version back to disk
        if filteredValues.count != existingValues.count {
            for removedKey in Set(existingValues.keys).subtracting(filteredValues.keys).sorted() {
                print("\(resourceFile.filename): Removed \(removedKey)")
            }
            let dataValue = try PropertyListSerialization.data(fromPropertyList: filteredValues, format: .xml, options: 0)
            try dataValue.write(to: stringsDictURL, options: [.atomic])
        }
    }

    private static func loadExistingValues(at url: URL) throws -> [String: Any] {
        let decodedPropertyList = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        guard let result = decodedPropertyList as? [String: Any] else {
            throw DecodingError.nonStringKeys
        }
        return result
    }

    private static func loadExpectedKeys(at url: URL) throws -> Set<String> {
        Set(try String(contentsOf: url).propertyListFromStringsFileFormat().keys)
    }
}
