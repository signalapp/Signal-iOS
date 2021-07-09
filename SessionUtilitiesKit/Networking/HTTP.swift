import Foundation
import PromiseKit

public enum HTTP {
    private static let seedNodeURLSession = URLSession(configuration: .ephemeral, delegate: seedNodeURLSessionDelegate, delegateQueue: nil)
    private static let seedNodeURLSessionDelegate = SeedNodeURLSessionDelegateImplementation()
    private static let snodeURLSession = URLSession(configuration: .ephemeral, delegate: snodeURLSessionDelegate, delegateQueue: nil)
    private static let snodeURLSessionDelegate = SnodeURLSessionDelegateImplementation()

    // MARK: Certificates
    private static let storageSeed1Cert: SecCertificate = {
        let path = Bundle.main.path(forResource: "storage-seed-1", ofType: "der")!
        let data = try! Data(contentsOf: URL(fileURLWithPath: path))
        return SecCertificateCreateWithData(nil, data as CFData)!
    }()
    
    private static let storageSeed3Cert: SecCertificate = {
        let path = Bundle.main.path(forResource: "storage-seed-3", ofType: "der")!
        let data = try! Data(contentsOf: URL(fileURLWithPath: path))
        return SecCertificateCreateWithData(nil, data as CFData)!
    }()
    
    private static let publicLokiFoundationCert: SecCertificate = {
        let path = Bundle.main.path(forResource: "public-loki-foundation", ofType: "der")!
        let data = try! Data(contentsOf: URL(fileURLWithPath: path))
        return SecCertificateCreateWithData(nil, data as CFData)!
    }()
    
    // MARK: Settings
    public static let timeout: TimeInterval = 10

    // MARK: Seed Node URL Session Delegate Implementation
    private final class SeedNodeURLSessionDelegateImplementation : NSObject, URLSessionDelegate {

        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            guard let trust = challenge.protectionSpace.serverTrust else {
                return completionHandler(.cancelAuthenticationChallenge, nil)
            }
            // Mark the seed node certificates as trusted
            let certificates = [ storageSeed1Cert, storageSeed3Cert, publicLokiFoundationCert ]
            guard SecTrustSetAnchorCertificates(trust, certificates as CFArray) == errSecSuccess else {
                return completionHandler(.cancelAuthenticationChallenge, nil)
            }
            // Check that the presented certificate is one of the seed node certificates
            var result: SecTrustResultType = .invalid
            guard SecTrustEvaluate(trust, &result) == errSecSuccess else {
                return completionHandler(.cancelAuthenticationChallenge, nil)
            }
            switch result {
            case .proceed, .unspecified:
                // Unspecified indicates that evaluation reached an (implicitly trusted) anchor certificate without
                // any evaluation failures, but never encountered any explicitly stated user-trust preference. This
                // is the most common return value. The Keychain Access utility refers to this value as the "Use System
                // Policy," which is the default user setting.
                return completionHandler(.useCredential, URLCredential(trust: trust))
            default: return completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }
    
    // MARK: Snode URL Session Delegate Implementation
    private final class SnodeURLSessionDelegateImplementation : NSObject, URLSessionDelegate {

        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            // Snode to snode communication uses self-signed certificates but clients can safely ignore this
            completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
        }
    }

    // MARK: Verb
    public enum Verb : String {
        case get = "GET"
        case put = "PUT"
        case post = "POST"
        case delete = "DELETE"
    }

    // MARK: Error
    public enum Error : LocalizedError {
        case generic
        case httpRequestFailed(statusCode: UInt, json: JSON?)
        case invalidJSON

        public var errorDescription: String? {
            switch self {
            case .generic: return "An error occurred."
            case .httpRequestFailed(let statusCode, _): return "HTTP request failed with status code: \(statusCode)."
            case .invalidJSON: return "Invalid JSON."
            }
        }
    }

    // MARK: Main
    public static func execute(_ verb: Verb, _ url: String, timeout: TimeInterval = HTTP.timeout, useSeedNodeURLSession: Bool = false) -> Promise<JSON> {
        return execute(verb, url, body: nil, timeout: timeout, useSeedNodeURLSession: useSeedNodeURLSession)
    }

    public static func execute(_ verb: Verb, _ url: String, parameters: JSON?, timeout: TimeInterval = HTTP.timeout, useSeedNodeURLSession: Bool = false) -> Promise<JSON> {
        if let parameters = parameters {
            do {
                guard JSONSerialization.isValidJSONObject(parameters) else { return Promise(error: Error.invalidJSON) }
                let body = try JSONSerialization.data(withJSONObject: parameters, options: [ .fragmentsAllowed ])
                return execute(verb, url, body: body, timeout: timeout, useSeedNodeURLSession: useSeedNodeURLSession)
            } catch (let error) {
                return Promise(error: error)
            }
        } else {
            return execute(verb, url, body: nil, timeout: timeout, useSeedNodeURLSession: useSeedNodeURLSession)
        }
    }

    public static func execute(_ verb: Verb, _ url: String, body: Data?, timeout: TimeInterval = HTTP.timeout, useSeedNodeURLSession: Bool = false) -> Promise<JSON> {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = verb.rawValue
        request.httpBody = body
        request.timeoutInterval = timeout
        request.allHTTPHeaderFields?.removeValue(forKey: "User-Agent")
        request.setValue("WhatsApp", forHTTPHeaderField: "User-Agent") // Set a fake value
        request.setValue("en-us", forHTTPHeaderField: "Accept-Language") // Set a fake value
        let (promise, seal) = Promise<JSON>.pending()
        let urlSession = useSeedNodeURLSession ? seedNodeURLSession : snodeURLSession
        let task = urlSession.dataTask(with: request) { data, response, error in
            guard let data = data, let response = response as? HTTPURLResponse else {
                if let error = error {
                    SNLog("\(verb.rawValue) request to \(url) failed due to error: \(error).")
                } else {
                    SNLog("\(verb.rawValue) request to \(url) failed.")
                }
                // Override the actual error so that we can correctly catch failed requests in sendOnionRequest(invoking:on:with:)
                return seal.reject(Error.httpRequestFailed(statusCode: 0, json: nil))
            }
            if let error = error {
                SNLog("\(verb.rawValue) request to \(url) failed due to error: \(error).")
                // Override the actual error so that we can correctly catch failed requests in sendOnionRequest(invoking:on:with:)
                return seal.reject(Error.httpRequestFailed(statusCode: 0, json: nil))
            }
            let statusCode = UInt(response.statusCode)
            var json: JSON? = nil
            if let j = try? JSONSerialization.jsonObject(with: data, options: [ .fragmentsAllowed ]) as? JSON {
                json = j
            } else if let result = String(data: data, encoding: .utf8) {
                json = [ "result" : result ]
            }
            guard 200...299 ~= statusCode else {
                let jsonDescription = json?.prettifiedDescription ?? "no debugging info provided"
                SNLog("\(verb.rawValue) request to \(url) failed with status code: \(statusCode) (\(jsonDescription)).")
                return seal.reject(Error.httpRequestFailed(statusCode: statusCode, json: json))
            }
            if let json = json {
                seal.fulfill(json)
            } else {
                SNLog("Couldn't parse JSON returned by \(verb.rawValue) request to \(url).")
                return seal.reject(Error.invalidJSON)
            }
        }
        task.resume()
        return promise
    }
}
