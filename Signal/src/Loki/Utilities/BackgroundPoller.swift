import PromiseKit

@objc(LKBackgroundPoller)
public final class BackgroundPoller : NSObject {
    private static var closedGroupPoller: ClosedGroupPoller!

    private override init() { }

    @objc(pollWithCompletionHandler:)
    public static func poll(completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        var promises: [Promise<Void>] = []
        promises.append(AppEnvironment.shared.messageFetcherJob.run()) // FIXME: It'd be nicer to just use Poller directly
        closedGroupPoller = ClosedGroupPoller()
        promises.append(contentsOf: closedGroupPoller.pollOnce())
        var openGroups: [String:PublicChat] = [:]
        Storage.read { transaction in
            openGroups = LokiDatabaseUtilities.getAllPublicChats(in: transaction)
        }
        openGroups.values.forEach { openGroup in
            let poller = PublicChatPoller(for: openGroup)
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
