//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

enum ValidatableModelError: Error {
    case failedToValidate
}

protocol ValidatableModel {
    /// Contains pairs of constant instances, alongside base64-encoded JSON
    /// produced by serializing the instance at the time of writing.
    ///
    /// To maintain backwards-compatibility, all serialized data here must
    /// always decode successfully as the expected paired instance. If changes
    /// are made such that this old data fails to deserialize as expected, then
    /// data from old app versions in the wild may also fail to decode as
    /// expected.
    static var constants: [(Self, base64JsonData: Data)] { get }

    /// Validate this instance against the given model.
    ///
    /// Throws if validation failed.
    func validate(against: Self) throws
}

extension ValidatableModel where Self: Encodable {
    /// Prints this model's constants as base64-encoded JSON data, represented
    /// as a string.
    ///
    /// Use this when adding new constants, to get the JSON representation to
    /// hardcode.
    static func printHardcodedJsonDataForConstants() {
        for (idx, (constant, _)) in constants.enumerated() {
            let jsonData: Data = try! JSONEncoder().encode(constant)
            print("\(Self.self) constant \(idx): \(jsonData.base64EncodedString())")
        }
    }
}
