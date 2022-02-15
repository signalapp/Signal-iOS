import PromiseKit

extension OpenGroupAPI {

    @objc(deleteMessageWithServerID:fromRoom:onServer:)
    public static func objc_deleteMessage(with serverID: Int64, from room: String, on server: String) -> AnyPromise {
        // TODO: Upgrade this to use the non-legacy version.
        return AnyPromise.from(legacyDeleteMessage(with: serverID, from: room, on: server))
    }
    
    @objc(legacyGetDefaultRoomsIfNeeded)
    public static func objc_legacyGetDefaultRoomsIfNeeded() {
        return legacyGetDefaultRoomsIfNeeded()
    }
}
