
internal extension LokiAPI {
    internal struct Request {
        var method: LokiAPITarget.Method
        var target: LokiAPITarget
        var publicKey: String
        var parameters: [String:Any]
        var headers: [String:String]
        var timeout: TimeInterval?
        
        init(method: LokiAPITarget.Method, target: LokiAPITarget, publicKey: String, parameters: [String:Any] = [:]) {
            self.method = method
            self.target = target
            self.publicKey = publicKey
            self.parameters = parameters
            self.headers = [:]
            self.timeout = nil
        }
    }
}
