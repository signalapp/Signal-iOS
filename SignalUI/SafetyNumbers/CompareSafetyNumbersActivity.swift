//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

let CompareSafetyNumbersActivityType = "org.whispersystems.signal.activity.CompareSafetyNumbers"

enum CompareSafetyNumberError: Error {
    case userError
    case verificationError

    var localizedError: String {
        switch self {
        case .userError:
            OWSLocalizedString("PRIVACY_VERIFICATION_FAILED_NO_SAFETY_NUMBERS_IN_CLIPBOARD", comment: "Alert body for user error")
        case .verificationError:
            OWSLocalizedString("PRIVACY_VERIFICATION_FAILED_MISMATCHED_SAFETY_NUMBERS_IN_CLIPBOARD", comment: "Alert body")
        }
    }
}

protocol CompareSafetyNumbersActivityDelegate: AnyObject {
    func compareSafetyNumbersActivitySucceeded(activity: CompareSafetyNumbersActivity)
    func compareSafetyNumbersActivity(_ activity: CompareSafetyNumbersActivity, failedWithError error: CompareSafetyNumberError)
}

final public class CompareSafetyNumbersActivity: UIActivity {

    var mySafetyNumbers: String?
    weak var delegate: CompareSafetyNumbersActivityDelegate?

    init(delegate: CompareSafetyNumbersActivityDelegate) {
        self.delegate = delegate
        super.init()
    }

    // MARK: UIActivity

    public override class var activityCategory: UIActivity.Category { .action }

    public override var activityType: UIActivity.ActivityType? {
        UIActivity.ActivityType(rawValue: CompareSafetyNumbersActivityType)
    }

    public override var activityTitle: String? {
        OWSLocalizedString("COMPARE_SAFETY_NUMBER_ACTION", comment: "Activity Sheet label")
    }

    public override var activityImage: UIImage? { UIImage(imageLiteralResourceName: "lock") }

    public override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        return stringsFrom(activityItems: activityItems).count > 0
    }

    public override func prepare(withActivityItems activityItems: [Any]) {
        let myFormattedSafetyNumbers = stringsFrom(activityItems: activityItems).first
        mySafetyNumbers = numericOnly(string: myFormattedSafetyNumbers)
    }

    public override func perform() {
        defer { activityDidFinish(true) }

        guard let delegate = delegate else {
            owsFailDebug("Missing delegate.")
            return
        }

        let pasteboardNumerics = numericOnly(string: UIPasteboard.general.string)
        guard let pasteboardString = pasteboardNumerics, pasteboardString.count == 60 else {
            Logger.warn("no valid safety numbers found in pasteboard")
            delegate.compareSafetyNumbersActivity(self, failedWithError: .userError)
            return
        }

        let pasteboardSafetyNumbers = pasteboardString

        if pasteboardSafetyNumbers == mySafetyNumbers {
            Logger.info("successfully matched safety numbers")
            delegate.compareSafetyNumbersActivitySucceeded(activity: self)
        } else {
            Logger.warn("local numbers didn't match pasteboard")
            delegate.compareSafetyNumbersActivity(self, failedWithError: .verificationError)
        }
    }

    // MARK: Helpers

    func numericOnly(string: String?) -> String? {
        guard let string = string else {
            return nil
        }

        var numericOnly: String?
        if let regex = try? NSRegularExpression(pattern: "\\D", options: .caseInsensitive) {
            numericOnly = regex.stringByReplacingMatches(in: string, options: .withTransparentBounds, range: string.entireRange, withTemplate: "")
        }

        return numericOnly
    }

    func stringsFrom(activityItems: [Any]) -> [String] {
        return activityItems.map { $0 as? String }.filter { $0 != nil }.map { $0! }
    }
}
