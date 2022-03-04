import PromiseKit
import SessionSnodeKit

@objc(SNFileServerAPIV2)
public final class FileServerAPIV2 : NSObject {
    
    // MARK: - Settings
    
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
    
    // MARK: - Initialization
    
    private override init() { }
    
    // MARK: - File Storage
    
    @objc(upload:)
    public static func objc_upload(file: Data) -> AnyPromise {
        return AnyPromise.from(upload(file).map { String($0) })
    }
    
    public static func upload(_ file: Data) -> Promise<UInt64> {
        let requestBody: FileUploadBody = FileUploadBody(file: file.base64EncodedString())
        
        let request = Request(
            method: .post,
            server: server,
            endpoint: Endpoint.files,
            body: requestBody
        )
        
        return send(request, serverPublicKey: serverPublicKey)
            .decoded(as: LegacyFileUploadResponse.self, on: .global(qos: .userInitiated), error: HTTP.Error.parsingFailed)
            .map { response in response.fileId }
    }
    
    @objc(download:useOldServer:)
    public static func objc_download(file: String, useOldServer: Bool) -> AnyPromise {
        guard let id = UInt64(file) else { return AnyPromise.from(Promise<Data>(error: HTTP.Error.invalidURL)) }
        return AnyPromise.from(download(id, useOldServer: useOldServer))
    }
    
    public static func download(_ file: UInt64, useOldServer: Bool) -> Promise<Data> {
        let serverPublicKey: String = (useOldServer ? oldServerPublicKey : serverPublicKey)
        let request = Request<NoBody, Endpoint>(
            server: (useOldServer ? oldServer : server),
            endpoint: .file(fileId: file)
        )
        
        return send(request, serverPublicKey: serverPublicKey)
            .decoded(as: LegacyFileDownloadResponse.self, on: .global(qos: .userInitiated), error: HTTP.Error.parsingFailed)
            .map { response in response.data }
    }

    public static func getVersion(_ platform: String) -> Promise<String> {
        let request = Request<NoBody, Endpoint>(
            server: server,
            endpoint: .sessionVersion,
            queryParameters: [
                .platform: platform
            ]
        )
        
        return send(request, serverPublicKey: serverPublicKey)
            .decoded(as: VersionResponse.self, on: .global(qos: .userInitiated), error: HTTP.Error.parsingFailed)
            .map { response in response.version }
    }
    
    // MARK: - Convenience
    
    private static func send<T: Encodable>(_ request: Request<T, Endpoint>, serverPublicKey: String) -> Promise<Data> {
        guard request.useOnionRouting else {
            preconditionFailure("It's currently not allowed to send non onion routed requests.")
        }
        
        let urlRequest: URLRequest
        
        do {
            urlRequest = try request.generateUrlRequest()
        }
        catch {
            return Promise(error: error)
        }
        
        // TODO: Rename file to be 'FileServerAPI' (drop the 'V2')
        return OnionRequestAPI.sendOnionRequest(urlRequest, to: request.server, with: serverPublicKey)
            .map2 { _, response in
                guard let response: Data = response else { throw HTTP.Error.parsingFailed }
                
                return response
            }
    }
}
