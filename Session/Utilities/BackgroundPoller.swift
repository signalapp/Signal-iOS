import PromiseKit

@objc(LKBackgroundPoller)
public final class BackgroundPoller : NSObject {
    private static var closedGroupPoller: ClosedGroupPoller!

    private override init() { }

    @objc(pollWithCompletionHandler:)
    public static func poll(completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        var promises: [Promise<Void>] = []
        // TODO TODO TODO
//        promises.append(AppEnvironment.shared.messageFetcherJob.run()) // FIXME: It'd be nicer to just use Poller directly
        closedGroupPoller = ClosedGroupPoller()
        promises.append(contentsOf: closedGroupPoller.pollOnce())
        let openGroups: [String:OpenGroup] = Storage.shared.getAllUserOpenGroups()
        openGroups.values.forEach { openGroup in
            let poller = OpenGroupPoller(for: openGroup)
            poller.stop()
            promises.append(poller.pollForNewMessages())
        }
        when(resolved: promises).done { _ in
            completionHandler(.newData)
        }.catch { _ in
            completionHandler(.failed)
        }
    }
}
