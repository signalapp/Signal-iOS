import Foundation
import SessionUtilitiesKit

// MARK: - Convenience Types

struct Empty: Codable {}

typealias NoBody = Empty
typealias NoResponse = Empty

protocol EndpointType: Hashable {
    var path: String { get }
}

// MARK: - Request

struct Request<T: Encodable, Endpoint: EndpointType> {
    let method: HTTP.Verb
    let server: String
    let endpoint: Endpoint
    let queryParameters: [QueryParam: String]
    let headers: [Header: String]
    /// This is the body value sent during the request
    ///
    /// **Warning:** The `bodyData` value should be used to when making the actual request instead of this as there
    /// is custom handling for certain data types
    let body: T?
    
    // MARK: - Initialization

    init(
        method: HTTP.Verb = .get,
        server: String,
        endpoint: Endpoint,
        queryParameters: [QueryParam: String] = [:],
        headers: [Header: String] = [:],
        body: T? = nil
    ) {
        self.method = method
        self.server = server
        self.endpoint = endpoint
        self.queryParameters = queryParameters
        self.headers = headers
        self.body = body
    }
    
    // MARK: - Internal Methods
    
    private var url: URL? {
        return URL(string: "\(server)\(urlPathAndParamsString)")
    }
    
    private func bodyData() throws -> Data? {
        // Note: Need to differentiate between JSON, b64 string and bytes body values to ensure they are
        // encoded correctly so the server knows how to handle them
        switch body {
            case let bodyString as String:
                // The only acceptable string body is a base64 encoded one
                guard let encodedData: Data = Data(base64Encoded: bodyString) else { throw HTTP.Error.parsingFailed }
                
                return encodedData
                
            case let bodyBytes as [UInt8]:
                return Data(bodyBytes)
                
            default:
                // Having no body is fine so just return nil
                guard let body: T = body else { return nil }

                return try JSONEncoder().encode(body)
        }
    }
    
    // MARK: - Request Generation
    
    var urlPathAndParamsString: String {
        return [
            "/\(endpoint.path)",
            queryParameters
                .map { key, value in "\(key.rawValue)=\(value)" }
                .joined(separator: "&")
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: "?")
    }
    
    func generateUrlRequest() throws -> URLRequest {
        guard let url: URL = url else { throw HTTP.Error.invalidURL }
        
        var urlRequest: URLRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue
        urlRequest.allHTTPHeaderFields = headers.toHTTPHeaders()
        urlRequest.httpBody = try bodyData()
        
        return urlRequest
    }
}

extension Request: Equatable where T: Equatable {}
