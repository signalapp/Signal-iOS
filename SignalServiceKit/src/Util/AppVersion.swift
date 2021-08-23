//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

extension AppVersion {

    // A parsed 3-dotted-value version string, e.g. 1.2.3.
    private struct AppVersion3 {
        let major: Int
        let minor: Int
        let patch: Int

        var formatted: String {
            "\(major).\(minor).\(patch)"
        }

        static func parse(_ value: String) -> AppVersion3 {
            let regex = try! NSRegularExpression(pattern: "^(\\d+)\\.(\\d+)\\.(\\d+)$", options: [])
            let match = regex.firstMatch(in: value, options: [], range: value.entireRange)!
            func group(_ index: Int) -> String {
                let matchRange = match.range(at: index)
                let stringRange = Range(matchRange, in: value)!
                return String(value[stringRange])
            }
            let major = Int(group(1))!
            let minor = Int(group(2))!
            let patch = Int(group(3))!
            let version = AppVersion3(major: major, minor: minor, patch: patch)
            owsAssert(value == version.formatted)
            return version
        }
    }

    // A parsed 4-dotted-value version string, e.g. 1.2.3.4.
    private struct AppVersion4 {
        let major: Int
        let minor: Int
        let patch: Int
        let build: Int

        var formatted: String {
            "\(major).\(minor).\(patch).\(build)"
        }
    }

    private static var parseAppReleaseVersion: AppVersion3 {
        let string = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        // Verify value has expected format.
        return AppVersion3.parse(string)
    }

    @objc
    public static var parseAppReleaseVersionString: String {
        parseAppReleaseVersion.formatted
    }

    private static var parseAppBuildVersion3: AppVersion3 {
        let string = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
        // Verify value has expected format.
        return AppVersion3.parse(string)
    }

    @objc
    public static var parseAppBuildVersion3String: String {
        parseAppBuildVersion3.formatted
    }

    // Internally, we use a version format with 4 dotted values
    // to uniquely identify builds. The first three values are the
    // the release version, the fourth value is the last value from
    // the build version.
    @objc
    public static var parseAppVersion4String: String {
        let appReleaseVersion = self.parseAppReleaseVersion
        let appBuildVersion3 = self.parseAppBuildVersion3
        let appVersion4 = AppVersion4(major: appReleaseVersion.major,
                                      minor: appReleaseVersion.minor,
                                      patch: appReleaseVersion.patch,
                                      build: appBuildVersion3.patch)
        return appVersion4.formatted
    }
}
