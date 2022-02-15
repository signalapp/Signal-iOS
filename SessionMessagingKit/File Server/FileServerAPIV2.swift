import PromiseKit
import SessionSnodeKit

@objc(SNFileServerAPIV2)
public final class FileServerAPIV2 : NSObject {
    
    // MARK: Settings
    @objc public static let oldServer = "http://88.99.175.227"
    public static let oldServerPublicKey = "7cb31905b55cd5580c686911debf672577b3fb0bff81df4ce2d5c4cb3a7aaa69"
    @objc public static let server = "http://filev2.getsession.org"
    public static let serverPublicKey = "da21e1d886c6fbaea313f75298bd64aab03a97ce985b46bb2dad9f2089c8ee59"
    public static let maxFileSize = 10_000_000 // 10 MB
    /// The file server has a file size limit of `maxFileSize`, which the Service Nodes try to enforce as well. However, the limit applied by the Service Nodes
    /// is on the **HTTP request** and not the actual file size. Because the file server expects the file data to be base 64 encoded, the size of the HTTP
    /// request for a given file will be at least `ceil(n / 3) * 4` bytes, where n is the file size in bytes. This is the minimum size because there might also
    /// be other parameters in the request. On average the multiplier appears to be about 1.5, so when checking whether the file will exceed the file size limit when
    /// uploading a file we just divide the size of the file by this number. The alternative would be to actually check the size of the HTTP request but that's only
    /// possible after proof of work has been calculated and the onion request encryption has happened, which takes several seconds.
    public static let fileSizeORMultiplier: Double = 2
    
    // MARK: Initialization
    private override init() { }
    
    // MARK: Error
    public enum Error: LocalizedError {
        case parsingFailed
        case invalidURL
        case maxFileSizeExceeded
        
        public var errorDescription: String? {
            switch self {
                case .parsingFailed: return "Invalid response."
                case .invalidURL: return "Invalid URL."
                case .maxFileSizeExceeded: return "Maximum file size exceeded."
            }
        }
    }
    
    // MARK: Request
    private struct Request {
        let verb: HTTP.Verb
        let endpoint: String
        let queryParameters: [QueryParam: String]
        let body: Data?
        let headers: [Header: String]
        /// Always `true` under normal circumstances. You might want to disable
        /// this when running over Lokinet.
        let useOnionRouting: Bool

        init(verb: HTTP.Verb, endpoint: String, queryParameters: [QueryParam: String] = [:], body: Data? = nil,
            headers: [Header: String] = [:], useOnionRouting: Bool = true) {
            self.verb = verb
            self.endpoint = endpoint
            self.queryParameters = queryParameters
            self.body = body
            self.headers = headers
            self.useOnionRouting = useOnionRouting
        }
    }
    
    // MARK: - Convenience
    
    private static func send(_ request: Request, useOldServer: Bool) -> Promise<Data> {
        let server = useOldServer ? oldServer : server
        let serverPublicKey = useOldServer ? oldServerPublicKey : serverPublicKey
        var urlRequest: URLRequest
        // TODO: Combine this 'Request' with the the pattern in OpenGroupServerV2?
        switch request.verb {
            case .get:
                var rawURL = "\(server)/\(request.endpoint)"
                
                if !request.queryParameters.isEmpty {
                    let queryString = request.queryParameters.map { key, value in "\(key)=\(value)" }.joined(separator: "&")
                    rawURL += "?\(queryString)"
                }
                
                guard let url = URL(string: rawURL) else { return Promise(error: Error.invalidURL) }
                
                urlRequest = URLRequest(url: url)
                
            case .post, .put, .delete:
                let rawURL = "\(server)/\(request.endpoint)"
                
                guard let url = URL(string: rawURL) else { return Promise(error: Error.invalidURL) }
                
                urlRequest = URLRequest(url: url)
                urlRequest.httpMethod = request.verb.rawValue
                urlRequest.httpBody = request.body
        }
        
        urlRequest.allHTTPHeaderFields = request.headers.toHTTPHeaders()
        
        guard request.useOnionRouting else {
            preconditionFailure("It's currently not allowed to send non onion routed requests.")
        }
        
        // TODO: Upgrade this to use the V4 onion requests once supported.
        return OnionRequestAPI.sendOnionRequest(urlRequest, to: server, using: .v3, with: serverPublicKey)
            .map2 { json in try JSONSerialization.data(withJSONObject: json, options: []) }
    }
    
    // MARK: File Storage
    @objc(upload:)
    public static func objc_upload(file: Data) -> AnyPromise {
        return AnyPromise.from(upload(file).map { String($0) })
    }
    
    public static func upload(_ file: Data) -> Promise<UInt64> {
        let requestBody: FileUploadBody = FileUploadBody(file: file.base64EncodedString())
        
        guard let body: Data = try? JSONEncoder().encode(requestBody) else {
            return Promise(error: HTTP.Error.invalidJSON)
        }
        
        let request = Request(verb: .post, endpoint: "files", body: body)
        return send(request, useOldServer: false).map(on: DispatchQueue.global(qos: .userInitiated)) { data in
            let response: LegacyFileUploadResponse = try data.decoded(as: LegacyFileUploadResponse.self, customError: Error.parsingFailed)
            
            return response.fileId
        }
    }
    
    @objc(download:useOldServer:)
    public static func objc_download(file: String, useOldServer: Bool) -> AnyPromise {
        guard let id = UInt64(file) else { return AnyPromise.from(Promise<Data>(error: Error.invalidURL)) }
        return AnyPromise.from(download(id, useOldServer: useOldServer))
    }
    
    public static func download(_ file: UInt64, useOldServer: Bool) -> Promise<Data> {
        let request = Request(verb: .get, endpoint: "files/\(file)")
        
        return send(request, useOldServer: useOldServer).map(on: DispatchQueue.global(qos: .userInitiated)) { data in
            let response: LegacyFileDownloadResponse = try data.decoded(as: LegacyFileDownloadResponse.self, customError: Error.parsingFailed)
            
            return response.data
        }
    }

    public static func getVersion(_ platform: String) -> Promise<String> {
        let request = Request(verb: .get, endpoint: "session_version?platform=\(platform)")
        
        return send(request, useOldServer: false).map(on: DispatchQueue.global(qos: .userInitiated)) { data in
            let response: VersionResponse = try data.decoded(as: VersionResponse.self, customError: Error.parsingFailed)
            
            return response.version
        }
    }
}
