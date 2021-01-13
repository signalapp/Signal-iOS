import PromiseKit

public protocol OpenGroupManagerProtocol {

    func addOpenGroup(with url: String) -> Promise<Void>
}
