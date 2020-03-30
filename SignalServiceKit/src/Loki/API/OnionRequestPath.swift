
/// A path used for making onion requests. See the "Onion Requests" section of
/// [The Session Whitepaper](https://arxiv.org/pdf/2002.04609.pdf) for more information.
struct OnionRequestPath : Hashable, CustomStringConvertible {
    let guardSnode: LokiAPITarget
    let snode1: LokiAPITarget
    let snode2: LokiAPITarget

    var description: String {
        return "\(guardSnode)-\(snode1)-\(snode2)"
    }
}
