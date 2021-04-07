import PromiseKit

extension OpenGroupAPIV2 {

    @objc(deleteMessageWithServerID:fromRoom:onServer:)
    public static func objc_deleteMessage(with serverID: Int64, from room: String, on server: String) -> AnyPromise {
        return AnyPromise.from(deleteMessage(with: serverID, from: room, on: server))
    }

    @objc(isUserModerator:forRoom:onServer:)
    public static func objc_isUserModerator(_ publicKey: String, for room: String, on server: String) -> Bool {
        return isUserModerator(publicKey, for: room, on: server)
    }
    
    @objc(getDefaultRoomsIfNeeded)
    public static func objc_getDefaultRoomsIfNeeded() {
        return getDefaultRoomsIfNeeded()
    }
}
