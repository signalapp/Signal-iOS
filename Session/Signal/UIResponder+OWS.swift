//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

// Based on https://stackoverflow.com/questions/1823317/get-the-current-first-responder-without-using-a-private-api/11768282#11768282
extension UIResponder {
    private weak static var firstResponder: UIResponder?

    @objc
    public class func currentFirstResponder() -> UIResponder? {
        firstResponder = nil

        // If target (`to:`) is nil, the app sends the message to the first responder,
        // from whence it progresses up the responder chain until it is handled.
        UIApplication.shared.sendAction(#selector(setSelfAsFirstResponder(sender:)), to: nil, from: nil, for: nil)

        return firstResponder
    }

    @objc
    private func setSelfAsFirstResponder(sender: AnyObject) {
        UIResponder.firstResponder = self
    }
}
