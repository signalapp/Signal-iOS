import PromiseKit
import SessionSnodeKit

@objc(SNFileServerAPIV2)
public final class FileServerAPIV2 : NSObject {
    
    // MARK: Settings
    @objc public static let server = "http://88.99.175.227"
    public static let serverPublicKey = "7cb31905b55cd5580c686911debf672577b3fb0bff81df4ce2d5c4cb3a7aaa69"
    
    // MARK: Initialization
    private override init() { }
    
    // MARK: Error
    public enum Error : LocalizedError {
        case parsingFailed
        case invalidURL
        
        public var errorDescription: String? {
            switch self {
            case .parsingFailed: return "Invalid response."
            case .invalidURL: return "Invalid URL."
            }
        }
    }
    
    // MARK: Request
    private struct Request {
        let verb: HTTP.Verb
        let endpoint: String
        let queryParameters: [String:String]
        let parameters: JSON
        let headers: [String:String]
        /// Always `true` under normal circumstances. You might want to disable
        /// this when running over Lokinet.
        let useOnionRouting: Bool

        init(verb: HTTP.Verb, endpoint: String, queryParameters: [String:String] = [:], parameters: JSON = [:],
            headers: [String:String] = [:], useOnionRouting: Bool = true) {
            self.verb = verb
            self.endpoint = endpoint
            self.queryParameters = queryParameters
            self.parameters = parameters
            self.headers = headers
            self.useOnionRouting = useOnionRouting
        }
    }
    
    // MARK: Convenience
    private static func send(_ request: Request) -> Promise<JSON> {
        let tsRequest: TSRequest
        switch request.verb {
        case .get:
            var rawURL = "\(server)/\(request.endpoint)"
            if !request.queryParameters.isEmpty {
                let queryString = request.queryParameters.map { key, value in "\(key)=\(value)" }.joined(separator: "&")
                rawURL += "?\(queryString)"
            }
            guard let url = URL(string: rawURL) else { return Promise(error: Error.invalidURL) }
            tsRequest = TSRequest(url: url)
        case .post, .put, .delete:
            let rawURL = "\(server)/\(request.endpoint)"
            guard let url = URL(string: rawURL) else { return Promise(error: Error.invalidURL) }
            tsRequest = TSRequest(url: url, method: request.verb.rawValue, parameters: request.parameters)
        }
        tsRequest.allHTTPHeaderFields = request.headers
        if request.useOnionRouting {
            return OnionRequestAPI.sendOnionRequest(tsRequest, to: server, using: serverPublicKey)
        } else {
            preconditionFailure("It's currently not allowed to send non onion routed requests.")
        }
    }
    
    // MARK: File Storage
    @objc(upload:)
    public static func objc_upload(file: Data) -> AnyPromise {
        return AnyPromise.from(upload(file))
    }
    
    public static func upload(_ file: Data) -> Promise<UInt64> {
        let base64EncodedFile = file.base64EncodedString()
        let parameters = [ "file" : base64EncodedFile ]
        let request = Request(verb: .post, endpoint: "files", parameters: parameters)
        return send(request).map(on: DispatchQueue.global(qos: .userInitiated)) { json in
            guard let fileID = json["result"] as? UInt64 else { throw Error.parsingFailed }
            return fileID
        }
    }
    
    @objc(download:)
    public static func objc_download(file: UInt64) -> AnyPromise {
        return AnyPromise.from(download(file))
    }
    
    public static func download(_ file: UInt64) -> Promise<Data> {
        let request = Request(verb: .get, endpoint: "files/\(file)")
        return send(request).map(on: DispatchQueue.global(qos: .userInitiated)) { json in
            guard let base64EncodedFile = json["result"] as? String, let file = Data(base64Encoded: base64EncodedFile) else { throw Error.parsingFailed }
            return file
        }
    }
}
