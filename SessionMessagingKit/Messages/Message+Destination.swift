
public extension Message {

    enum Destination {
        case contact(publicKey: String)
        case closedGroup(groupPublicKey: String)
        case openGroup(channel: UInt64, server: String)
    }
}
