//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

extension NSItemProvider {
    func loadUrl(forTypeIdentifier typeIdentifier: String, options: [AnyHashable: Any]?) -> Promise<URL> {
        return Promise { resolver in
            self.ows_loadUrl(forTypeIdentifier: typeIdentifier, options: options) { url, error in
                if let error = error {
                    resolver.reject(error)
                    return
                }

                guard let url = url else {
                    resolver.reject(OWSAssertionError("url was unexpectedly nil"))
                    return
                }

                resolver.fulfill(url)
            }
        }
    }

    func loadData(forTypeIdentifier typeIdentifier: String, options: [AnyHashable: Any]?) -> Promise<Data> {
        return Promise { resolver in
            self.ows_loadData(forTypeIdentifier: typeIdentifier, options: options) { data, error in
                if let error = error {
                    resolver.reject(error)
                    return
                }

                guard let data = data else {
                    resolver.reject(OWSAssertionError("data was unexpectedly nil"))
                    return
                }

                resolver.fulfill(data)
            }
        }
    }

    func loadText(forTypeIdentifier typeIdentifier: String, options: [AnyHashable: Any]?) -> Promise<String> {
        return Promise { resolver in
            self.ows_loadText(forTypeIdentifier: typeIdentifier, options: options) { text, error in
                if let error = error {
                    resolver.reject(error)
                    return
                }

                guard let text = text else {
                    resolver.reject(OWSAssertionError("data was unexpectedly nil"))
                    return
                }

                resolver.fulfill(text)
            }
        }
    }

    func loadImage(forTypeIdentifier typeIdentifier: String, options: [AnyHashable: Any]?) -> Promise<UIImage> {
        return Promise { resolver in
            self.ows_loadImage(forTypeIdentifier: typeIdentifier, options: options) { image, error in
                if let error = error {
                    resolver.reject(error)
                    return
                }

                guard let image = image else {
                    resolver.reject(OWSAssertionError("image was unexpectedly nil"))
                    return
                }

                resolver.fulfill(image)
            }
        }
    }
}
