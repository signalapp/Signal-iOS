
extension Storage {

    private static let volumeSamplesCollection = "LokiVolumeSamplesCollection"

    public func getVolumeSamples(for attachment: String) -> [Float]? {
        var result: [Float]?
        Storage.read { transaction in
            result = transaction.object(forKey: attachment, inCollection: Storage.volumeSamplesCollection) as? [Float]
        }
        return result
    }

    public func setVolumeSamples(for attachment: String, to volumeSamples: [Float], using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(volumeSamples, forKey: attachment, inCollection: Storage.volumeSamplesCollection)
    }
}
