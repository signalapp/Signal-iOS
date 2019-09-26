import PromiseKit

public class LokiDotNetAPI : NSObject {

    // MARK: Convenience
    private static let userKeyPair = OWSIdentityManager.shared().identityKeyPair()!
    internal static let storage = OWSPrimaryStorage.shared()
    internal static let userHexEncodedPublicKey = userKeyPair.hexEncodedPublicKey

    // MARK: Error
    public enum Error : Swift.Error {
        case parsingFailed, decryptionFailed
    }

    // MARK: Database
    /// To be overridden by subclasses.
    internal class var authTokenCollection: String { preconditionFailure("authTokenCollection is abstract and must be overridden.") }

    private static func getAuthTokenFromDatabase(for server: String) -> String? {
        var result: String? = nil
        storage.dbReadConnection.read { transaction in
            result = transaction.object(forKey: server, inCollection: authTokenCollection) as! String?
        }
        return result
    }

    private static func setAuthToken(for server: String, to newValue: String) {
        storage.dbReadWriteConnection.readWrite { transaction in
            transaction.setObject(newValue, forKey: server, inCollection: authTokenCollection)
        }
    }

    // MARK: Lifecycle
    override private init() { }

    // MARK: Internal API
    internal static func getAuthToken(for server: String) -> Promise<String> {
        if let token = getAuthTokenFromDatabase(for: server) {
            return Promise.value(token)
        } else {
            return requestNewAuthToken(for: server).then { submitAuthToken($0, for: server) }.map { token -> String in
                setAuthToken(for: server, to: token)
                return token
            }
        }
    }

    // MARK: Private API
    private static func requestNewAuthToken(for server: String) -> Promise<String> {
        print("[Loki] Requesting auth token for server: \(server).")
        let queryParameters = "pubKey=\(userHexEncodedPublicKey)"
        let url = URL(string: "\(server)/loki/v1/get_challenge?\(queryParameters)")!
        let request = TSRequest(url: url)
        return TSNetworkManager.shared().makePromise(request: request).map { $0.responseObject }.map { rawResponse in
            guard let json = rawResponse as? JSON, let base64EncodedChallenge = json["cipherText64"] as? String, let base64EncodedServerPublicKey = json["serverPubKey64"] as? String,
                let challenge = Data(base64Encoded: base64EncodedChallenge), var serverPublicKey = Data(base64Encoded: base64EncodedServerPublicKey) else {
                throw Error.parsingFailed
            }
            // Discard the "05" prefix if needed
            if (serverPublicKey.count == 33) {
                let hexEncodedServerPublicKey = serverPublicKey.hexadecimalString
                serverPublicKey = Data.data(fromHex: hexEncodedServerPublicKey.substring(from: 2))!
            }
            // The challenge is prefixed by the 16 bit IV
            guard let tokenAsData = try? DiffieHellman.decrypt(challenge, publicKey: serverPublicKey, privateKey: userKeyPair.privateKey),
                let token = String(bytes: tokenAsData, encoding: .utf8) else {
                throw Error.decryptionFailed
            }
            return token
        }
    }

    private static func submitAuthToken(_ token: String, for server: String) -> Promise<String> {
        print("[Loki] Submitting auth token for server: \(server).")
        let url = URL(string: "\(server)/loki/v1/submit_challenge")!
        let parameters = [ "pubKey" : userHexEncodedPublicKey, "token" : token ]
        let request = TSRequest(url: url, method: "POST", parameters: parameters)
        return TSNetworkManager.shared().makePromise(request: request).map { _ in token }
    }
}
