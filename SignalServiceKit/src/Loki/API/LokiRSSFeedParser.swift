
public final class LokiRSSFeedParser : NSObject, XMLParserDelegate {
    private let url: URL
    private var completion: (([Item]) -> Void)?
    private var tag: Tag?
    private var currentItem: Item?
    private var items: [Item] = []
    
    private enum Tag : String {
        case item, title, description, date = "pubDate"
    }
    
    public struct Item {
        public var title: String? = nil
        public var description: String? = nil
        public var dateAsString: String? = nil
    }
    
    public init(url: URL) {
        self.url = url
        super.init()
    }
    
    public func parse(completion: @escaping (([Item]) -> Void)) {
        guard let parser = XMLParser(contentsOf: url) else { return }
        self.completion = completion
        parser.delegate = self
        parser.parse()
    }
    
    public func parser(_ parser: XMLParser, didStartElement elementAsString: String, namespaceURI: String?, qualifiedName: String?, attributes: [String:String] = [:]) {
        if let element = Tag(rawValue: elementAsString) { self.tag = element }
        if tag == .item { currentItem = Item() }
    }
    
    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard let element = tag else { return }
        switch element {
        case .title: currentItem?.title = string
        case .description: currentItem?.description = string
        case .date: currentItem?.dateAsString = string
        default: break
        }
    }
    
    public func parser(_ parser: XMLParser, didEndElement elementAsString: String, namespaceURI: String?, qualifiedName: String?) {
        guard let element = Tag(rawValue: elementAsString) else { return }
        if element == .item, let currentItem = self.currentItem { items.append(currentItem) }
    }
    
    public func parserDidEndDocument(_ parser: XMLParser) {
        completion?(items)
    }
}
