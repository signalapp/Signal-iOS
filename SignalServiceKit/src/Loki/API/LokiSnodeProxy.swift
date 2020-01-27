import PromiseKit

internal class LokiSnodeProxy : LokiHTTPClient {
    internal let target: LokiAPITarget
    private let keyPair: ECKeyPair
    
    private lazy var httpSession: AFHTTPSessionManager = {
        let result = AFHTTPSessionManager(sessionConfiguration: .ephemeral)
        let securityPolicy = AFSecurityPolicy.default()
        securityPolicy.allowInvalidCertificates = true
        securityPolicy.validatesDomainName = false
        result.securityPolicy = securityPolicy
        result.responseSerializer = AFHTTPResponseSerializer()
        return result
    }()
    
    // MARK: Error
    internal enum Error : LocalizedError {
        case targetPublicKeySetMissing
        case symmetricKeyGenerationFailed
        case proxyResponseParsingFailed
        case targetSnodeHTTPError(code: Int, message: Any?)
           
        internal var errorDescription: String? {
           switch self {
           case .targetPublicKeySetMissing: return "Missing target public key set"
           case .symmetricKeyGenerationFailed: return "Couldn't generate symmetric key"
           case .proxyResponseParsingFailed: return "Couldn't parse proxy response"
           case .targetSnodeHTTPError(let httpStatusCode, let message): return "Target snode returned error \(httpStatusCode) with description: \(message ?? "no description provided")."
           }
        }
    }
    
    // MARK: Initialization
    internal init(for target: LokiAPITarget) {
        self.target = target
        keyPair = Curve25519.generateKeyPair()
        super.init()
    }
    
    // MARK: Proxying
    override internal func perform(_ request: TSRequest, withCompletionQueue queue: DispatchQueue = DispatchQueue.main) -> LokiAPI.RawResponsePromise {
        guard let targetHexEncodedPublicKeySet = target.publicKeySet else { return Promise(error: Error.targetPublicKeySetMissing) }
        let uncheckedSymmetricKey = try? Curve25519.generateSharedSecret(fromPublicKey: Data(hex: targetHexEncodedPublicKeySet.encryptionKey), privateKey: keyPair.privateKey)
        guard let symmetricKey = uncheckedSymmetricKey else { return Promise(error: Error.symmetricKeyGenerationFailed) }
        let headers = getCanonicalHeaders(for: request)
        return LokiAPI.getRandomSnode().then { [target = self.target, keyPair = self.keyPair, httpSession = self.httpSession] proxy -> Promise<Any> in
            let url = "\(proxy.address):\(proxy.port)/proxy"
            print("[Loki] Proxying request to \(target) through \(proxy).")
            let parametersAsData = try JSONSerialization.data(withJSONObject: request.parameters, options: [])
            let proxyRequestParameters: [String:Any] = [
                "method" : request.httpMethod,
                "body" : String(bytes: parametersAsData, encoding: .utf8),
                "headers" : headers
            ]
            let proxyRequestParametersAsData = try JSONSerialization.data(withJSONObject: proxyRequestParameters, options: [])
            let ivAndCipherText = try DiffieHellman.encrypt(proxyRequestParametersAsData, using: symmetricKey)
            let proxyRequestHeaders = [
                "X-Sender-Public-Key" : keyPair.publicKey.map { String(format: "%02hhx", $0) }.joined(),
                "X-Target-Snode-Key" : targetHexEncodedPublicKeySet.idKey
            ]
            let (promise, resolver) = LokiAPI.RawResponsePromise.pending()
            let proxyRequest = AFHTTPRequestSerializer().request(withMethod: "POST", urlString: url, parameters: nil, error: nil)
            proxyRequest.allHTTPHeaderFields = proxyRequestHeaders
            proxyRequest.httpBody = ivAndCipherText
            proxyRequest.timeoutInterval = request.timeoutInterval
            var task: URLSessionDataTask!
            task = httpSession.dataTask(with: proxyRequest as URLRequest) { response, result, error in
                if let error = error {
                    let nmError = NetworkManagerError.taskError(task: task, underlyingError: error)
                    let nsError: NSError = nmError as NSError
                    nsError.isRetryable = false
                    resolver.reject(nsError)
                } else {
                    OutageDetection.shared.reportConnectionSuccess()
                    resolver.fulfill(result)
                }
            }
            task.resume()
            return promise
        }.map { rawResponse in
            guard let data = rawResponse as? Data, let cipherText = Data(base64Encoded: data) else {
                print("[Loki] Received a non-string encoded response.")
                return rawResponse
            }
            let response = try DiffieHellman.decrypt(cipherText, using: symmetricKey)
            let uncheckedJSON = try? JSONSerialization.jsonObject(with: response, options: .allowFragments) as? JSON
            guard let json = uncheckedJSON, let httpStatusCode = json["status"] as? Int else { throw HTTPError.networkError(code: -1, response: nil, underlyingError: Error.proxyResponseParsingFailed) }
            let isSuccess = (200..<300).contains(httpStatusCode)
            var body: Any? = nil
            if let bodyAsString = json["body"] as? String {
                body = bodyAsString
                if let bodyAsJSON = try? JSONSerialization.jsonObject(with: bodyAsString.data(using: .utf8)!, options: .allowFragments) as? [String: Any] {
                    body = bodyAsJSON
                }
            }
            guard isSuccess else { throw HTTPError.networkError(code: httpStatusCode, response: body, underlyingError: Error.targetSnodeHTTPError(code: httpStatusCode, message: body)) }
            return body
        }.recover { error -> Promise<Any> in
            print("[Loki] Proxy request failed with error: \(error.localizedDescription).")
            throw HTTPError.from(error: error) ?? error
        }
    }
    
    // MARK: Convenience
    private func getCanonicalHeaders(for request: TSRequest) -> [String: Any] {
        guard let headers = request.allHTTPHeaderFields else { return [:] }
        return headers.mapValues { value in
            switch value.lowercased() {
            case "true": return true
            case "false": return false
            default: return value
            }
        }
    }
}
