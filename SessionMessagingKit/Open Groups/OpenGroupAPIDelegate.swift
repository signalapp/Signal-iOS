
public protocol OpenGroupAPIDelegate {

    func updateProfileIfNeeded(for channel: UInt64, on server: String, from info: OpenGroupInfo)
}
