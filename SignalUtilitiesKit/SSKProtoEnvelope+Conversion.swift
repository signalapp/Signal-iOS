
extension SSKProtoEnvelope {

    static func from(_ json: JSON) -> SSKProtoEnvelope? {
        guard let base64EncodedData = json["data"] as? String, let data = Data(base64Encoded: base64EncodedData) else {
            print("[Loki] Failed to decode data for message: \(json).")
            return nil
        }
        guard let result = try? MessageWrapper.unwrap(data: data) else {
            print("[Loki] Failed to unwrap data for message: \(json).")
            return nil
        }
        return result
    }
}
