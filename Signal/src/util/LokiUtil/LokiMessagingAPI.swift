import PromiseKit
import LokiKit

public struct LokiMessagingAPI {
    
    private static var snodeURL: String { return textSecureServerURL }
    private static var port: String { return "8080" }
    private static var apiVersion: String { return "v1" }
    
    // MARK: Types
    private enum Method : String {
        case retrieveAllMessages = "retrieve"
        case send = "store"
    }
    
    public typealias Response = TSNetworkManager.NetworkManagerResult
    
    // MARK: Lifecycle
    private init() { }
    
    // MARK: API
    private static func invoke(_ method: Method, parameters: [String:String] = [:]) -> Promise<Response> {
        let url = URL(string: "\(snodeURL):\(port)/\(apiVersion)/storage_rpc")!
        let request = TSRequest(url: url, method: "POST", parameters: [ "method" : method.rawValue, "params" : parameters ])
        return TSNetworkManager.shared().makePromise(request: request)
    }
    
    public static func sendTestMessage() -> Promise<Response> {
        let hour = 60 * 60 * 1000
        let ttl = String(4 * 24 * hour)
        let parameters = [
            "pubKey" : "0371e72be8dd42ff77105e474a3ac26a503d017fb4562409c639eaf5965f5b31", // TODO: Receiver's public key
            "ttl" : ttl,
            "nonce" : "AAAAAAAA5rs=", // TODO: Proof of work
            "timestamp" : "1556259498201", // TODO: Message send time
            "data" : "CAESvgMKA1BVVBIPL2FwaS92MS9tZXNzYWdlGqIDCGUSQjA1MDM3MWU3MmJlOGRkNDJmZjc3MTA1ZTQ3NGEzYWMyNmE1MDNkMDE3ZmI0NTYyNDA5YzYzOWVhZjU5NjVmNWIzYzgBKK3QrcKlLULQAlxclJTbzKeQjJPfPlvo0VdoNw+O6kmpAUAKz2Mmz0YDHnhIsFgdWlBIoudqxVDu7swq5Z4cUqMfcQ5Z0b03/dVjkmFYo79Hzv7wkmRlPsfqAOVLBgV06sLVl+C5d8EmDtfH+k2iT62HnD8fub8tIxHn2l0MCefB4kO8tbA4dl/n/IXlvRAFS7OPJiq3jLyykyZkauAW7SVdDBAO6exJlNyOHTgSaHF924V3a/s3BK0useVMbzJSun9cx68Jm3WGERMFqrd75X70PN933zUSHedBAmMFW1Mvecko1G854tfNPZllP7OO/o+6XrQm8hMoe0Zo3POelrXwRdX88jp9VSEio/Yugq9MMcBuMsU5G0ePK5ZJMNfGLwExGSLY4br3sYpJz5yO7slpq2GgPuO6t9hWwIfzWynvNIfVtDxBkLVSV5XZU7720p/KP6kqZWCGHyCsAQ==" // TODO: Encrypted content
        ]
        return invoke(.send, parameters: parameters)
    }
    
    public static func retrieveAllMessages() -> Promise<Response> {
        let parameters = [
            "pubKey" : OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey,
            "lastHash" : ""
        ]
        return invoke(.retrieveAllMessages, parameters: parameters)
    }
}
