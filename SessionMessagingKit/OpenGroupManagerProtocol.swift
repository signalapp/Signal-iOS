import PromiseKit

public protocol OpenGroupManagerProtocol {

    func addOpenGroup(with url: String, using transaction: Any) -> Promise<Void>
}
