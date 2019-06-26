import GCDWebServer

private extension GCDWebServerResponse {
    
    convenience init<E: RawRepresentable>(statusCode: E) where E.RawValue == Int {
        self.init(statusCode: statusCode.rawValue)
    }
}

private extension GCDWebServerDataRequest {
    
    var truncatedContentType: String? {
        guard let contentType = contentType else { return nil }
        guard let substring = contentType.split(separator: ";").first else { return contentType }
        return String(substring)
    }
    
    // GCDWebServerDataRequest already provides this implementation
    // However it will abort when running in DEBUG, we don't want that so we just override it with a version which doesn't abort
    var jsonObject: JSON? {
        let acceptedMimeTypes = [ "application/json", "text/json", "text/javascript" ]
        guard let mimeType = truncatedContentType, acceptedMimeTypes.contains(mimeType) else { return nil }
        
        do {
            let object = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
            return object as? JSON
        } catch let error {
            print("[Loki] Failed to serialize JSON: \(error).")
        }
        
        return nil
    }
}

@objc(LKP2PServer)
final class LokiP2PServer : NSObject {
    
    private enum StatusCode : Int {
        case ok = 200
        case badRequest = 400
        case notFound = 404
        case methodNotAllowed = 405
        case internalServerError = 500
    }
    
    private lazy var webServer: GCDWebServer = {
        let webServer = GCDWebServer()
        
         // Don't allow specific methods
        let invalidMethodProcessBlock: (GCDWebServerRequest) -> GCDWebServerResponse? = { _ in
            return GCDWebServerResponse(statusCode: StatusCode.methodNotAllowed)
        }
        
        let invalidMethods = [ "GET", "PUT", "DELETE" ]
        for method in invalidMethods {
            webServer.addDefaultHandler(forMethod: method, request: GCDWebServerRequest.self, processBlock: invalidMethodProcessBlock)
        }
        
        // By default send 404 for any path
        webServer.addDefaultHandler(forMethod: "POST", request: GCDWebServerRequest.self, processBlock: { _ in
            return GCDWebServerResponse(statusCode: StatusCode.notFound)
        })
        
        // Handle our specific storage path
        webServer.addHandler(forMethod: "POST", path: "/storage_rpc/v1", request: GCDWebServerDataRequest.self, processBlock: { request in
            // Make sure we were sent a good request
            guard let dataRequest = request as? GCDWebServerDataRequest, let json = dataRequest.jsonObject else {
                return GCDWebServerResponse(statusCode: StatusCode.badRequest)
            }
            
            // Only allow the store method
            guard let method = json["method"] as? String, method == "store" else {
                return GCDWebServerResponse(statusCode: StatusCode.notFound)
            }
            
            // Make sure we have the data
            guard let params = json["params"] as? [String: String], let data = params["data"] else {
                return GCDWebServerResponse(statusCode: StatusCode.badRequest)
            }
            
            // Pass it off to the message handler
            LokiP2PAPI.handleReceivedMessage(base64EncodedData: data)
            
            // Send a response back
            return GCDWebServerResponse(statusCode: StatusCode.ok.rawValue)
        })
        
        return webServer
    }()
    
    @objc public var serverURL: URL? { return webServer.serverURL }
    @objc public var isRunning: Bool { return webServer.isRunning }

    @discardableResult
    @objc func start(onPort port: UInt) -> Bool  {
        guard !webServer.isRunning else { return false }
        webServer.start(withPort: port, bonjourName: nil)
        return webServer.isRunning
    }
    
    @objc func stop() { webServer.stop() }
}
