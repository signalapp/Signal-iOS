import PromiseKit

extension OpenGroupAPI {
    @objc(deleteMessageWithServerID:fromRoom:onServer:)
    public static func objc_deleteMessage(with serverID: Int64, from room: String, on server: String) -> AnyPromise {
        return AnyPromise.from(messageDelete(serverID, in: room, on: server))
    }
}
