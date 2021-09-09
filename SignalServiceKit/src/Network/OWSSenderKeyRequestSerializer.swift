//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import AFNetworking

class OWSSenderKeyBodyRequestSerializer: AFHTTPRequestSerializer {
    let senderKeyBody: Data
    init(senderKeyBody: Data) {
        self.senderKeyBody = senderKeyBody
        super.init()
    }

    required init?(coder: NSCoder) {
        senderKeyBody = Data()
        super.init(coder: coder)
    }

    override func request(bySerializingRequest request: URLRequest, withParameters parameters: Any?, error: NSErrorPointer) -> URLRequest? {
        var mutableRequest = request

        httpRequestHeaders.forEach {
            if mutableRequest.value(forHTTPHeaderField: $0.key) == nil {
                mutableRequest.setValue($0.value, forHTTPHeaderField: $0.key)
            }
        }

        // Don't mess around with trying to parse an untyped parameters argument. We have they bytes,
        // just set it on the request.
        if mutableRequest.value(forHTTPHeaderField: "Content-Type") == nil {
            mutableRequest.setValue(kSenderKeySendRequestBodyContentType, forHTTPHeaderField: "Content-Type")
        }
        mutableRequest.httpBody = senderKeyBody
        return mutableRequest
    }
}
