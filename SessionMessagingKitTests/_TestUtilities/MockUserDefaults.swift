// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionUtilitiesKit

class MockUserDefaults: Mock<UserDefaultsType>, UserDefaultsType {
    func object(forKey defaultName: String) -> Any? { return accept(args: [defaultName]) }
    func string(forKey defaultName: String) -> String? { return accept(args: [defaultName]) as? String }
    func array(forKey defaultName: String) -> [Any]? { return accept(args: [defaultName]) as? [Any] }
    func dictionary(forKey defaultName: String) -> [String: Any]? { return accept(args: [defaultName]) as? [String: Any] }
    func data(forKey defaultName: String) -> Data? { return accept(args: [defaultName]) as? Data }
    func stringArray(forKey defaultName: String) -> [String]? { return accept(args: [defaultName]) as? [String] }
    func integer(forKey defaultName: String) -> Int { return ((accept(args: [defaultName]) as? Int) ?? 0) }
    func float(forKey defaultName: String) -> Float { return ((accept(args: [defaultName]) as? Float) ?? 0) }
    func double(forKey defaultName: String) -> Double { return ((accept(args: [defaultName]) as? Double) ?? 0) }
    func bool(forKey defaultName: String) -> Bool { return ((accept(args: [defaultName]) as? Bool) ?? false) }
    func url(forKey defaultName: String) -> URL? { return accept(args: [defaultName]) as? URL }

    func set(_ value: Any?, forKey defaultName: String) { accept(args: [value, defaultName]) }
    func set(_ value: Int, forKey defaultName: String) { accept(args: [value, defaultName]) }
    func set(_ value: Float, forKey defaultName: String) { accept(args: [value, defaultName]) }
    func set(_ value: Double, forKey defaultName: String) { accept(args: [value, defaultName]) }
    func set(_ value: Bool, forKey defaultName: String) { accept(args: [value, defaultName]) }
    func set(_ url: URL?, forKey defaultName: String) { accept(args: [url, defaultName]) }
}
