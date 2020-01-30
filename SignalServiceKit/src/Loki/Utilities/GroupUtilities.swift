
public enum GroupUtilities {

    public static func getClosedGroupMembers(_ closedGroup: TSGroupThread) -> [String] {
        var result: [String]!
        OWSPrimaryStorage.shared().dbReadConnection.read { transaction in
            result = getClosedGroupMembers(closedGroup, with: transaction)
        }
        return result
    }

    public static func getClosedGroupMembers(_ closedGroup: TSGroupThread, with transaction: YapDatabaseReadTransaction) -> [String] {
        let userHexEncodedPublicKey = getUserHexEncodedPublicKey()
        let linkedDeviceHexEncodedPublicKeys = LokiDatabaseUtilities.getLinkedDeviceHexEncodedPublicKeys(for: userHexEncodedPublicKey, in: transaction)
        return closedGroup.groupModel.groupMemberIds.filter { !linkedDeviceHexEncodedPublicKeys.contains($0) }
    }

    public static func getClosedGroupMemberCount(_ closedGroup: TSGroupThread) -> Int {
        return getClosedGroupMembers(closedGroup).count
    }

    public static func getClosedGroupMemberCount(_ closedGroup: TSGroupThread, with transaction: YapDatabaseReadTransaction) -> Int {
        return getClosedGroupMembers(closedGroup, with: transaction).count
    }
}
