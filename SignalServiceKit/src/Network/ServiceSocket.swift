//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

protocol ServiceSocket {
    func getAvailablePreKeys() -> Promise<Int>
    func registerPreKeys(identityKey: IdentityKey, signedPreKeyRecord: SignedPreKeyRecord, preKeyRecords: [PreKeyRecord]) -> Promise<Void>
}

class ServiceRestSocket: ServiceSocket {

    var networkManager: TSNetworkManager {
        return TSNetworkManager.shared()
    }

    func unexpectedServerResponseError() -> Error {
        return OWSErrorMakeUnableToProcessServerResponseError()
    }

    func getAvailablePreKeys() -> Promise<Int> {
        Logger.debug("")

        let (promise, fulfill, reject) = Promise<Int>.pending()

        let request = OWSRequestFactory.availablePreKeysCountRequest()
        networkManager.makeRequest(request,
                                   success: { (_, responseObject) in
                                    Logger.debug("got response")
                                    guard let params = ParamParser(responseObject: responseObject) else {
                                        reject(self.unexpectedServerResponseError())
                                        return
                                    }

                                    let count: Int
                                    do {
                                        count = try params.required(key: "count")
                                    } catch {
                                        reject(error)
                                        return
                                    }

                                    fulfill(count)
        },
                                   failure: { (_, error) in
                                    Logger.debug("error: \(error)")
                                    reject(error)
        })
        return promise
    }

    func registerPreKeys(identityKey: IdentityKey, signedPreKeyRecord: SignedPreKeyRecord, preKeyRecords: [PreKeyRecord]) -> Promise<Void> {
        Logger.debug("")

        let (promise, fulfill, reject) = Promise<Void>.pending()
        let request = OWSRequestFactory.registerPrekeysRequest(withPrekeyArray: preKeyRecords, identityKey: identityKey, signedPreKey: signedPreKeyRecord)

        networkManager.makeRequest(request,
                                   success: { (_, _) in
                                    Logger.debug("success")
                                    fulfill(())

        },
                                   failure: { (_, error) in
                                    Logger.debug("error: \(error)")
                                    reject(error)
        })
        return promise
    }
}
