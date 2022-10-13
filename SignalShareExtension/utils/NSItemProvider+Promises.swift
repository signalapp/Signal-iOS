//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension NSItemProvider {
    func loadUrl(forTypeIdentifier typeIdentifier: String, options: [AnyHashable: Any]?) -> Promise<URL> {
        return Promise { future in
            self.ows_loadUrl(forTypeIdentifier: typeIdentifier, options: options) { url, error in
                if let error = error {
                    future.reject(error)
                    return
                }

                guard let url = url else {
                    future.reject(OWSAssertionError("url was unexpectedly nil"))
                    return
                }

                future.resolve(url)
            }
        }
    }

    func loadData(forTypeIdentifier typeIdentifier: String, options: [AnyHashable: Any]?) -> Promise<Data> {
        return Promise { future in
            self.ows_loadData(forTypeIdentifier: typeIdentifier, options: options) { data, error in
                if let error = error {
                    future.reject(error)
                    return
                }

                guard let data = data else {
                    future.reject(OWSAssertionError("data was unexpectedly nil"))
                    return
                }

                future.resolve(data)
            }
        }
    }

    func loadText(forTypeIdentifier typeIdentifier: String, options: [AnyHashable: Any]?) -> Promise<String> {
        return Promise { future in
            self.ows_loadText(forTypeIdentifier: typeIdentifier, options: options) { text, error in
                if let error = error {
                    future.reject(error)
                    return
                }

                guard let text = text else {
                    future.reject(OWSAssertionError("data was unexpectedly nil"))
                    return
                }

                future.resolve(text)
            }
        }
    }

    func loadImage(forTypeIdentifier typeIdentifier: String, options: [AnyHashable: Any]?) -> Promise<UIImage> {
        return Promise { future in
            self.ows_loadImage(forTypeIdentifier: typeIdentifier, options: options) { image, error in
                if let error = error {
                    future.reject(error)
                    return
                }

                guard let image = image else {
                    future.reject(OWSAssertionError("image was unexpectedly nil"))
                    return
                }

                future.resolve(image)
            }
        }
    }
}
