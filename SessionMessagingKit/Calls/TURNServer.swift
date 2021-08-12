import PromiseKit

enum MockTURNSserver {
    
    static func getICEServerURL() -> Promise<String> {
        HTTP.execute(.get, "https://appr.tc/params").map2 { json in
            guard let url = json["ice_server_url"] as? String else { throw HTTP.Error.invalidJSON }
            return url
        }
    }
    
    static func makeTurnServerRequest(iceServerURL: String) -> Promise<JSON> {
        let headers = [ "referer" : "https://appr.tc" ]
        return HTTP.execute(.post, iceServerURL, body: nil, headers: headers)
    }
}
