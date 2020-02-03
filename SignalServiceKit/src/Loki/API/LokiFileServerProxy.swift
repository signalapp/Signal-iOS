import PromiseKit

internal class LokiFileServerProxy : LokiHTTPClient {
    private let server: String
    private let keyPair = Curve25519.generateKeyPair()

    private static let fileServerPublicKey: Data = {
        let base64EncodedPublicKey = "BWJQnVm97sQE3Q1InB4Vuo+U/T1hmwHBv0ipkiv8tzEc"
        let publicKeyWithPrefix = Data(base64Encoded: base64EncodedPublicKey)!
        let hexEncodedPublicKeyWithPrefix = publicKeyWithPrefix.toHexString()
        let hexEncodedPublicKey = hexEncodedPublicKeyWithPrefix.removing05PrefixIfNeeded()
        return Data(hex: hexEncodedPublicKey)
    }()

    // MARK: Error
    internal enum Error : LocalizedError {
        case symmetricKeyGenerationFailed
        case endpointParsingFailed
        case proxyResponseParsingFailed
        case fileServerHTTPError(code: Int, message: Any?)

        internal var errorDescription: String? {
           switch self {
           case .symmetricKeyGenerationFailed: return "Couldn't generate symmetric key."
           case .endpointParsingFailed: return "Couldn't parse endpoint."
           case .proxyResponseParsingFailed: return "Couldn't parse proxy response."
           case .fileServerHTTPError(let httpStatusCode, let message): return "File server returned error \(httpStatusCode) with description: \(message ?? "no description provided.")."
           }
        }
    }

    // MARK: Initialization
    internal init(for server: String) {
        self.server = server
        super.init()
    }

    // MARK: Proxying
    override internal func perform(_ request: TSRequest, withCompletionQueue queue: DispatchQueue = DispatchQueue.main) -> LokiAPI.RawResponsePromise {
        let isLokiFileServer = server.contains("file.lokinet.org") || server.contains("file-dev.lokinet.org")
        guard isLokiFileServer else { return super.perform(request, withCompletionQueue: queue) } // Don't proxy open group requests for now
        let uncheckedSymmetricKey = try? Curve25519.generateSharedSecret(fromPublicKey: LokiFileServerProxy.fileServerPublicKey, privateKey: keyPair.privateKey)
        guard let symmetricKey = uncheckedSymmetricKey else { return Promise(error: Error.symmetricKeyGenerationFailed) }
        var headers = getCanonicalHeaders(for: request)
        headers["Content-Type"] = "application/json"
        return LokiAPI.getRandomSnode().then { [server = self.server, keyPair = self.keyPair, httpSession = self.httpSession] proxy -> Promise<Any> in
            let url = "\(proxy.address):\(proxy.port)/file_proxy"
            print("[Loki] Proxying request to \(server) through \(proxy).")
            guard let urlAsString = request.url?.absoluteString, let serverURLEndIndex = urlAsString.range(of: server)?.upperBound,
                serverURLEndIndex < urlAsString.endIndex else { throw Error.endpointParsingFailed }
            let endpointStartIndex = urlAsString.index(after: serverURLEndIndex)
            let endpoint = String(urlAsString[endpointStartIndex..<urlAsString.endIndex])
            let parametersAsData = try JSONSerialization.data(withJSONObject: request.parameters, options: [])
            let parametersAsString = !request.parameters.isEmpty ? String(bytes: parametersAsData, encoding: .utf8)! : "null"
            let proxyRequestParameters: JSON = [
                "body" : parametersAsString,
                "endpoint": endpoint,
                "method" : request.httpMethod,
                "headers" : headers
            ]
            let proxyRequestParametersAsData = try JSONSerialization.data(withJSONObject: proxyRequestParameters, options: [])
            let ivAndCipherText = try DiffieHellman.encrypt(proxyRequestParametersAsData, using: symmetricKey)
            let base64EncodedPublicKey = Data(hex: keyPair.hexEncodedPublicKey).base64EncodedString() // The file server expects an 05 prefixed public key
            let proxyRequestHeaders = [
                "X-Loki-File-Server-Target" : "/loki/v1/secure_rpc",
                "X-Loki-File-Server-Verb" : "POST",
                "X-Loki-File-Server-Headers" : "{ \"X-Loki-File-Server-Ephemeral-Key\" : \"\(base64EncodedPublicKey)\" }",
                "Connection" : "close", // TODO: Is this necessary?
                "Content-Type" : "application/json"
            ]
            let (promise, resolver) = LokiAPI.RawResponsePromise.pending()
            let proxyRequest = AFHTTPRequestSerializer().request(withMethod: "POST", urlString: url, parameters: nil, error: nil)
            proxyRequest.allHTTPHeaderFields = proxyRequestHeaders
            proxyRequest.httpBody = "{ \"cipherText64\" : \"\(ivAndCipherText.base64EncodedString())\" }".data(using: String.Encoding.utf8)!
            proxyRequest.timeoutInterval = request.timeoutInterval
            var task: URLSessionDataTask!
            task = httpSession.dataTask(with: proxyRequest as URLRequest) { response, result, error in
                if let error = error {
                    let nmError = NetworkManagerError.taskError(task: task, underlyingError: error)
                    let nsError: NSError = nmError as NSError
                    nsError.isRetryable = false
                    resolver.reject(nsError)
                } else {
                    resolver.fulfill(result)
                }
            }
            task.resume()
            return promise
        }.map { rawResponse in
            guard let data = rawResponse as? Data, !data.isEmpty else {
                print("[Loki] Received an empty response.")
                return rawResponse
            }
            var uncheckedStatusCode: Int? = nil
            let uncheckedCipherText: Data?
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? JSON, let base64EncodedData = json["data"] as? String {
                if let meta = json["meta"] as? JSON { uncheckedStatusCode = meta["code"] as? Int }
                uncheckedCipherText = Data(base64Encoded: base64EncodedData)
            } else {
                uncheckedCipherText = data
            }
            guard let cipherText = uncheckedCipherText else {
                print("[Loki] Received an invalid response.")
                throw Error.proxyResponseParsingFailed
            }
            let response = try DiffieHellman.decrypt(cipherText, using: symmetricKey)
            let uncheckedJSON = try? JSONSerialization.jsonObject(with: response, options: .allowFragments) as? JSON
            guard let json = uncheckedJSON else { throw HTTPError.networkError(code: -1, response: nil, underlyingError: Error.proxyResponseParsingFailed) }
            if uncheckedStatusCode == nil {
                uncheckedStatusCode = json["status"] as? Int
            }
            guard let statusCode = uncheckedStatusCode else {
                print("[Loki] Received an invalid response.")
                throw Error.proxyResponseParsingFailed
            }
            let isSuccess = (200..<300).contains(statusCode)
            var body: Any? = nil
            if let bodyAsString = json["body"] as? String {
                body = bodyAsString
                if let bodyAsJSON = try? JSONSerialization.jsonObject(with: bodyAsString.data(using: .utf8)!, options: .allowFragments) as? JSON {
                    body = bodyAsJSON
                }
            }
            guard isSuccess else { throw HTTPError.networkError(code: statusCode, response: body, underlyingError: Error.fileServerHTTPError(code: statusCode, message: body)) }
            return body ?? response
        }.recover { error -> Promise<Any> in
            print("[Loki] File server proxy request failed with error: \(error.localizedDescription).")
            throw HTTPError.from(error: error) ?? error
        }
    }
}
