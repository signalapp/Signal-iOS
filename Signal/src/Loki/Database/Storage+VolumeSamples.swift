
extension Storage {

    static let volumeSamplesCollection = "LokiVolumeSamplesCollection"

    static func getVolumeSamples(for attachment: String) -> [Float]? {
        var result: [Float]?
        read { transaction in
            result = transaction.object(forKey: attachment, inCollection: volumeSamplesCollection) as? [Float]
        }
        return result
    }

    static func setVolumeSamples(for attachment: String, to volumeSamples: [Float], using transaction: YapDatabaseReadWriteTransaction) {
        transaction.setObject(volumeSamples, forKey: attachment, inCollection: volumeSamplesCollection)
    }
}
