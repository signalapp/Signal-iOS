import FeedKit

@objc(LKRSSFeedPoller)
public final class RSSFeedPoller : NSObject {
    private let feed: LokiRSSFeed
    private var timer: Timer? = nil
    private var hasStarted = false
    
    private let interval: TimeInterval = 8 * 60
    
    @objc(initForFeed:)
    public init(for feed: LokiRSSFeed) {
        self.feed = feed
        super.init()
    }
    
    @objc public func startIfNeeded() {
        if hasStarted { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.poll() }
        poll() // Perform initial update
        hasStarted = true
    }
    
    @objc public func stop() {
        timer?.invalidate()
        hasStarted = false
    }
    
    private func poll() {
        let feed = self.feed
        let url = URL(string: feed.server)!
        FeedParser(URL: url).parseAsync { wrapper in
            guard case .rss(let x) = wrapper, let items = x.items else { return print("[Loki] Failed to parse RSS feed for: \(feed.server).") }
            items.reversed().forEach { item in
                guard let title = item.title, let description = item.description, let date = item.pubDate else { return }
                let timestamp = UInt64(date.timeIntervalSince1970 * 1000)
                let urlRegex = try! NSRegularExpression(pattern: "<a\\s+(?:[^>]*?\\s+)?href=\"([^\"]*)\".*?>(.*?)<.*?\\/a>")
                var bodyAsHTML = "\(title)<br><br>\(description)".replacingOccurrences(of: "</p>", with: "</p><br>")
                while true {
                    guard let match = urlRegex.firstMatch(in: bodyAsHTML, options: [], range: NSRange(location: 0, length: bodyAsHTML.utf16.count)) else { break }
                    let matchRange = match.range(at: 0)
                    let urlRange = match.range(at: 1)
                    let descriptionRange = match.range(at: 2)
                    let url = (bodyAsHTML as NSString).substring(with: urlRange)
                    let description = (bodyAsHTML as NSString).substring(with: descriptionRange)
                    bodyAsHTML = (bodyAsHTML as NSString).replacingCharacters(in: matchRange, with: "\(description) (\(url))") as String
                }
                guard let bodyAsData = bodyAsHTML.data(using: String.Encoding.unicode) else { return }
                let options = [ NSAttributedString.DocumentReadingOptionKey.documentType : NSAttributedString.DocumentType.html ]
                guard let body = try? NSAttributedString(data: bodyAsData, options: options, documentAttributes: nil).string else { return }
                let id = feed.id.data(using: String.Encoding.utf8)!
                let groupContext = SSKProtoGroupContext.builder(id: id, type: .deliver)
                groupContext.setName(feed.displayName)
                let dataMessage = SSKProtoDataMessage.builder()
                dataMessage.setTimestamp(timestamp)
                dataMessage.setGroup(try! groupContext.build())
                dataMessage.setBody(body)
                let content = SSKProtoContent.builder()
                content.setDataMessage(try! dataMessage.build())
                let envelope = SSKProtoEnvelope.builder(type: .ciphertext, timestamp: timestamp)
                envelope.setSource(NSLocalizedString("Loki", comment: ""))
                envelope.setSourceDevice(OWSDevicePrimaryDeviceId)
                envelope.setContent(try! content.build().serializedData())
                OWSPrimaryStorage.shared().dbReadWriteConnection.readWrite { transaction in
                    SSKEnvironment.shared.messageManager.throws_processEnvelope(try! envelope.build(), plaintextData: try! content.build().serializedData(), wasReceivedByUD: false, transaction: transaction)
                }
            }
        }
    }
}
