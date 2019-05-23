
internal extension LokiAPI {
    
    internal struct Target : Hashable {
        internal let address: String
        internal let port: UInt32
        
        internal init(address: String, port: UInt32) {
            self.address = address
            self.port = port
        }
        
        internal init(from targetWrapper: TargetWrapper) {
            self.address = targetWrapper.address
            self.port = targetWrapper.port
        }
        
        internal enum Method : String {
            /// Only supported by snode targets.
            case getSwarm = "get_snodes_for_pubkey"
            /// Only supported by snode targets.
            case getMessages = "retrieve"
            case sendMessage = "store"
        }
    }
}
