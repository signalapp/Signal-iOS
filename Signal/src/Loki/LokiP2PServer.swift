import GCDWebServer

@objc class LokiP2PServer : NSObject {
    private lazy var webServer: GCDWebServer = {
        let webServer = GCDWebServer()
        
        webServer.addHandler(forMethod: "POST", path: "/v1/storage_rpc", request: GCDWebServerRequest.self) { (request, completionBlock) in
            let response = GCDWebServerDataResponse(html: "<html><body><p>Hello World</p></body></html>")
            completionBlock(response)
        }
        
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
