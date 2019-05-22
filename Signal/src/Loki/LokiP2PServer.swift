import GCDWebServer

// Convenience functions
fileprivate extension GCDWebServerDataRequest {
    var truncatedContentType: String? {
        guard let contentType = contentType else { return nil }
        guard let substring = contentType.split(separator: ";").first else { return contentType }
        return String(substring)
    }
    
    // GCDWebServerDataRequest already provides this implementation
    // However it will abort when running in DEBUG, we don't want that so we just override it with a version which doesn't abort
    var jsonObject: [String: Any]? {
        let acceptedMimeTypes = ["application/json", "text/json", "text/javascript"]
        guard let mimeType = truncatedContentType, acceptedMimeTypes.contains(mimeType) else { return nil }
        
        do {
            let object = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
            return object as? [String: Any]
        } catch let error {
            Logger.debug("[Loki P2P Server] Failed to serialize json: \(error)")
        }
        
        return nil
    }
}

@objc class LokiP2PServer : NSObject {
    
    private enum StatusCode: Int {
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
            return GCDWebServerResponse(statusCode: StatusCode.methodNotAllowed.rawValue)
        }
        
        let invalidMethods = ["GET", "PUT", "DELETE"]
        for method in invalidMethods {
            webServer.addDefaultHandler(forMethod: method, request: GCDWebServerRequest.self, processBlock: invalidMethodProcessBlock)
        }
        
        // By default send 404 for any path
        webServer.addDefaultHandler(forMethod: "POST", request: GCDWebServerRequest.self, processBlock: { _ in
            return GCDWebServerResponse(statusCode: StatusCode.notFound.rawValue)
        })
        
        // Handle our specific storage path
        webServer.addHandler(forMethod: "POST", path: "/v1/storage_rpc", request: GCDWebServerDataRequest.self, asyncProcessBlock: { (request, completionBlock) in
            // Make sure we were sent a good request
            guard let dataRequest = request as? GCDWebServerDataRequest, let json = dataRequest.jsonObject else {
                completionBlock(GCDWebServerResponse(statusCode: StatusCode.badRequest.rawValue))
                return
            }
            
            // Only allow the store method
            guard let method = json["method"] as? String, method == "store" else {
                completionBlock(GCDWebServerResponse(statusCode: StatusCode.notFound.rawValue))
                return
            }
            
            // TODO: Decrypt message here
            
            let response = GCDWebServerResponse(statusCode: StatusCode.ok.rawValue)
            completionBlock(response)
        })
        
        return webServer
    }()
    
    @objc public var serverURL: URL? {
        return webServer.serverURL
    }
    
    @objc public var isRunning: Bool {
        return webServer.isRunning
    }
    
    @objc @discardableResult func start(onPort port: UInt) -> Bool  {
        guard !webServer.isRunning else { return false }
        webServer.start(withPort: port, bonjourName: nil)
        return true
    }
    
    @objc func stop() {
        webServer.stop()
    }
}
