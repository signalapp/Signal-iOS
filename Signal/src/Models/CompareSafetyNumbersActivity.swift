//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

let CompareSafetyNumbersActivityType = "org.whispersystems.signal.activity.CompareSafetyNumbers"

@objc(OWSCompareSafetyNumbersActivityDelegate)
protocol CompareSafetyNumbersActivityDelegate {
    func compareSafetyNumbersActivitySucceeded(activity: CompareSafetyNumbersActivity)
    func compareSafetyNumbersActivity(_ activity: CompareSafetyNumbersActivity, failedWithError error: Error)
}

@objc (OWSCompareSafetyNumbersActivity)
class CompareSafetyNumbersActivity: UIActivity {

    var mySafetyNumbers: String?
    weak var delegate: CompareSafetyNumbersActivityDelegate?

    @objc
    required init(delegate: CompareSafetyNumbersActivityDelegate) {
        self.delegate = delegate
        super.init()
    }

    // MARK: UIActivity

    override class var activityCategory: UIActivity.Category {
        get { return .action }
    }

    override var activityType: UIActivity.ActivityType? {
        get { return UIActivity.ActivityType(rawValue: CompareSafetyNumbersActivityType) }
    }

    override var activityTitle: String? {
        get {
            return NSLocalizedString("COMPARE_SAFETY_NUMBER_ACTION", comment: "Activity Sheet label")
        }
    }

    override var activityImage: UIImage? {
        get {
            return  #imageLiteral(resourceName: "ic_lock_outline")
        }
    }

    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        return stringsFrom(activityItems: activityItems).count > 0
    }

    override func prepare(withActivityItems activityItems: [Any]) {
        let myFormattedSafetyNumbers = stringsFrom(activityItems: activityItems).first
        mySafetyNumbers = numericOnly(string: myFormattedSafetyNumbers)
    }

    override func perform() {
        defer { activityDidFinish(true) }

        guard let delegate = delegate else {
            owsFailDebug("Missing delegate.")
            return
        }

        let pasteboardNumerics = numericOnly(string: UIPasteboard.general.string)
        guard let pasteboardString = pasteboardNumerics,
              pasteboardString.count == 60 else {
            Logger.warn("no valid safety numbers found in pasteboard: \(String(describing: pasteboardNumerics))")
            let error = OWSErrorWithCodeDescription(OWSErrorCode.userError,
                                                    NSLocalizedString("PRIVACY_VERIFICATION_FAILED_NO_SAFETY_NUMBERS_IN_CLIPBOARD", comment: "Alert body for user error"))

            delegate.compareSafetyNumbersActivity(self, failedWithError: error)
            return
        }

        let pasteboardSafetyNumbers = pasteboardString

        if pasteboardSafetyNumbers == mySafetyNumbers {
            Logger.info("successfully matched safety numbers. local numbers: \(String(describing: mySafetyNumbers)) pasteboard:\(pasteboardSafetyNumbers)")
            delegate.compareSafetyNumbersActivitySucceeded(activity: self)
        } else {
            Logger.warn("local numbers: \(String(describing: mySafetyNumbers)) didn't match pasteboard:\(pasteboardSafetyNumbers)")
            let error = OWSErrorWithCodeDescription(OWSErrorCode.privacyVerificationFailure,
                                                    NSLocalizedString("PRIVACY_VERIFICATION_FAILED_MISMATCHED_SAFETY_NUMBERS_IN_CLIPBOARD", comment: "Alert body"))
            delegate.compareSafetyNumbersActivity(self, failedWithError: error)
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
