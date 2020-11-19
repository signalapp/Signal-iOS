
public extension SNProtoEnvelope {

    static func from(_ json: JSON) -> SNProtoEnvelope? {
        guard let base64EncodedData = json["data"] as? String, let data = Data(base64Encoded: base64EncodedData) else {
            SNLog("Failed to decode data for message: \(json).")
            return nil
        }
        guard let result = try? MessageWrapper.unwrap(data: data) else {
            SNLog("Failed to unwrap data for message: \(json).")
            return nil
        }
        return result
    }
}
