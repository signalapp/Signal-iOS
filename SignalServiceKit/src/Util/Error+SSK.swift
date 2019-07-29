//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

extension NSError {
    @objc
    public func httpResponseCodeObjc() -> NSNumber? {
        guard let value = httpResponseCode() else {
            return nil
        }
        return NSNumber(value: value)
    }

    // TODO: Currently this method only works for AFNetworking errors.
    //       We could generalize it.
    public func httpResponseCode() -> Int? {
        guard domain == AFURLResponseSerializationErrorDomain else {
            return nil
        }
        guard let response = userInfo[AFNetworkingOperationFailingURLResponseErrorKey] as? HTTPURLResponse else {
            return nil
        }
        return response.statusCode
    }

    @objc
    public func hasFatalResponseCode() -> Bool {
        guard let responseCode = httpResponseCode() else {
            return false
        }
        if responseCode == 429 {
            // "Too Many Requests", retry with backoff.
            return false
        }
        return 400 <= responseCode && responseCode <= 499
    }
}
