import PromiseKit

internal enum LokiRSSFeedProxy {

    internal enum Error : LocalizedError {
        case proxyResponseParsingFailed

        internal var errorDescription: String? {
           switch self {
           case .proxyResponseParsingFailed: return "Couldn't parse proxy response."
           }
        }
    }

    internal static func fetchContent(for url: String) -> Promise<String> {
        let server = LokiStorageAPI.server
        let endpoints = [ "messenger-updates/feed" : "loki/v1/rss/messenger", "loki.network/feed" : "loki/v1/rss/loki" ]
        let endpoint = endpoints.first { url.lowercased().contains($0.key) }!.value
        let url = URL(string: server + "/" + endpoint)!
        let request = TSRequest(url: url)
        return LokiFileServerProxy(for: server).perform(request).map { response -> String in
            guard let json = response as? JSON, let data = json["data"] as? String else { throw Error.proxyResponseParsingFailed }
            return data
        }
    }
}
