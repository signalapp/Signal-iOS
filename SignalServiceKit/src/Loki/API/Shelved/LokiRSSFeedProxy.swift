import PromiseKit

public enum LokiRSSFeedProxy {

    public enum Error : LocalizedError {
        case proxyResponseParsingFailed

        public var errorDescription: String? {
           switch self {
           case .proxyResponseParsingFailed: return "Couldn't parse RSS feed proxy response."
           }
        }
    }

    public static func fetchContent(for url: String) -> Promise<String> {
        let server = FileServerAPI.server
        let endpoints = [ "messenger-updates/feed" : "loki/v1/rss/messenger", "loki.network/feed" : "loki/v1/rss/loki" ]
        let endpoint = endpoints.first { url.lowercased().contains($0.key) }!.value
        let url = URL(string: server + "/" + endpoint)!
        let request = TSRequest(url: url)
        return LokiFileServerProxy(for: server).perform(request).map2 { response -> String in
            guard let json = response as? JSON, let xml = json["data"] as? String else { throw Error.proxyResponseParsingFailed }
            return xml
        }
    }
}
