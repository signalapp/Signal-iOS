import PromiseKit

public protocol OpenGroupManagerProtocol {

    func add(with url: String, using transaction: Any) -> Promise<Void>
}
