
public struct MockCallConfig {
    public let signalingServerURL: String
    public let serverURL: String
    public let webRTCICEServers: [String]
    
    private static let defaultSignalingServerURL = "ws://developereric.com:8080"
    private static let defaultICEServers = [
        "stun:stun.l.google.com:19302",
        "stun:stun1.l.google.com:19302",
        "stun:stun2.l.google.com:19302",
        "stun:stun3.l.google.com:19302",
        "stun:stun4.l.google.com:19302"
    ]
    private static let defaultServerURL = "https://appr.tc"
    
    private init(signalingServerURL: String, serverURL: String, webRTCICEServers: [String]) {
        self.signalingServerURL = signalingServerURL
        self.serverURL = serverURL
        self.webRTCICEServers = webRTCICEServers
    }
    
    public static let `default` = MockCallConfig(signalingServerURL: defaultSignalingServerURL,
        serverURL: defaultServerURL, webRTCICEServers: defaultICEServers)
}
