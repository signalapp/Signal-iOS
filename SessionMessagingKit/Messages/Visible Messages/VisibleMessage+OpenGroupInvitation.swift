import SessionUtilitiesKit

public extension VisibleMessage {

    @objc(SNOpenGroupInvitation)
    class OpenGroupInvitation : NSObject, NSCoding {
        public var name: String?
        public var url: String?

        internal init(name: String, url: String) {
            self.name = name
            self.url = url
        }

        public required init?(coder: NSCoder) {
            if let name = coder.decodeObject(forKey: "name") as! String? { self.name = name }
            if let url = coder.decodeObject(forKey: "url") as! String? { self.url = url }
        }

        public func encode(with coder: NSCoder) {
            coder.encode(name, forKey: "name")
            coder.encode(url, forKey: "url")
        }

        public static func fromProto(_ proto: SNProtoDataMessage) -> Profile? {
            notImplemented()
        }

        public func toProto() -> SNProtoDataMessage? {
            notImplemented()
        }
        
        // MARK: Description
        public override var description: String {
            """
            OpenGroupInvitation(
                name: \(name ?? "null"),
                url: \(url ?? "null")
            )
            """
        }
    }
}
