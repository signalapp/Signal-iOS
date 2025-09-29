//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

enum EmojiPickerSection {
    case messageEmoji
    case recentEmoji
    case emojiCategory(categoryIndex: Int)
}

protocol EmojiPickerCollectionViewDelegate: AnyObject {
    func emojiPicker(_ emojiPicker: EmojiPickerCollectionView, didSelectEmoji emoji: EmojiWithSkinTones)
    func emojiPicker(_ emojiPicker: EmojiPickerCollectionView, didScrollToSection section: EmojiPickerSection)
    func emojiPickerWillBeginDragging(_ emojiPicker: EmojiPickerCollectionView)

}

final class EmojiPickerCollectionView: UICollectionView {
    let layout: UICollectionViewFlowLayout

    private static let keyValueStore = KeyValueStore(collection: "EmojiPickerCollectionView")
    private static let recentEmojiKey = "recentEmoji"

    /// Reads the stored recent emoji and removes duplicates using `removingNonNormalizedDuplicates`.
    static func getRecentEmoji(tx: DBReadTransaction) -> [EmojiWithSkinTones] {
        let recentEmojiStrings = keyValueStore.getStringArray(EmojiPickerCollectionView.recentEmojiKey, transaction: tx) ?? []

        return recentEmojiStrings
            .compactMap(EmojiWithSkinTones.init(rawValue:))
            .removingNonNormalizedDuplicates()
    }

    weak var pickerDelegate: EmojiPickerCollectionViewDelegate?

    // The emoji already applied to the message
    private let messageEmoji: [EmojiWithSkinTones]
    var hasMessageEmoji: Bool { !messageEmoji.isEmpty }

    private let recentEmoji: [EmojiWithSkinTones]
    var hasRecentEmoji: Bool { !recentEmoji.isEmpty }

    private let allSendableEmojiByCategory: [Emoji.Category: [EmojiWithSkinTones]]
    private lazy var allSendableEmoji: [EmojiWithSkinTones] = {
        return Array(allSendableEmojiByCategory.values).flatMap({$0})
    }()

    static let emojiWidth: CGFloat = 38
    static let margins: CGFloat = 16
    static let minimumSpacing: CGFloat = 10

    public var searchText: String? {
        didSet {
            searchWithText(searchText)
        }
    }

    private var emojiSearchResults: [EmojiWithSkinTones] = []
    private var emojiSearchLocalization: String?
    private var emojiSearchIndex: [String: [String]]?

    public var isSearching: Bool {
        if let searchText = searchText, !searchText.isEmpty {
            return true
        }

        return false
    }

    lazy var tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(dismissSkinTonePicker))

    private let forceDarkTheme: Bool

    init(
        message: TSMessage?,
        forceDarkTheme: Bool = false
    ) {
        self.forceDarkTheme = forceDarkTheme

        layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(square: EmojiPickerCollectionView.emojiWidth)
        layout.minimumInteritemSpacing = EmojiPickerCollectionView.minimumSpacing
        layout.sectionInset = UIEdgeInsets(top: 0, leading: EmojiPickerCollectionView.margins, bottom: 0, trailing: EmojiPickerCollectionView.margins)

        let messageReacts: [OWSReaction]
        (messageReacts, recentEmoji, allSendableEmojiByCategory) = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            let messageReacts: [OWSReaction]
            if let message {
                messageReacts = ReactionFinder(uniqueMessageId: message.uniqueId).allReactions(transaction: transaction)
            } else {
                messageReacts = []
            }

            let recentEmoji = EmojiPickerCollectionView.getRecentEmoji(tx: transaction)

            let allSendableEmojiByCategory = Emoji.allSendableEmojiByCategoryWithPreferredSkinTones(
                transaction: transaction
            )

            return (messageReacts, recentEmoji, allSendableEmojiByCategory)
        }
        // Remove duplicates while preserving order.
        var messageEmojiSet = Set<EmojiWithSkinTones>()
        var dedupedEmoji = [EmojiWithSkinTones]()
        for react in messageReacts {
            guard let emoji = EmojiWithSkinTones(rawValue: react.emoji) else {
                continue
            }
            guard !messageEmojiSet.contains(emoji.normalized) else {
                continue
            }
            messageEmojiSet.insert(emoji.normalized)
            dedupedEmoji.append(emoji)
        }
        self.messageEmoji = dedupedEmoji

        super.init(frame: .zero, collectionViewLayout: layout)

        delegate = self
        dataSource = self

        register(EmojiCell.self, forCellWithReuseIdentifier: EmojiCell.reuseIdentifier)
        register(
            EmojiSectionHeader.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: EmojiSectionHeader.reuseIdentifier
        )

        backgroundColor = (Theme.isDarkThemeEnabled || self.forceDarkTheme) ? .ows_gray80 : .ows_white

        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        panGestureRecognizer.require(toFail: longPressGesture)
        addGestureRecognizer(longPressGesture)

        addGestureRecognizer(tapGestureRecognizer)
        tapGestureRecognizer.delegate = self

        NotificationCenter.default.addObserver(self, selector: #selector(emojiSearchManifestUpdated), name: EmojiSearchIndex.EmojiSearchManifestFetchedNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(emojiSearchIndexUpdated), name: EmojiSearchIndex.EmojiSearchIndexFetchedNotification, object: nil)

        EmojiSearchIndex.updateManifestIfNeeded()
        emojiSearchLocalization = EmojiSearchIndex.searchIndexLocalizationForLocale(NSLocale.current.identifier)
        if let emojiSearchLocalization = emojiSearchLocalization {
            emojiSearchIndex = EmojiSearchIndex.emojiSearchIndex(for: emojiSearchLocalization, shouldFetch: true)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // This is not an exact calculation, but is simple and works for our purposes.
    var numberOfColumns: Int { Int((width) / (EmojiPickerCollectionView.emojiWidth + EmojiPickerCollectionView.minimumSpacing)) }

    // At max, we show 3 rows of recent emoji
    private var maxRecentEmoji: Int { numberOfColumns * 3 }

    private func section(raw: Int) -> EmojiPickerSection {
        switch (hasMessageEmoji, hasRecentEmoji) {
        case (true, true):
            // Message emoji, then recents, then categories.
            switch raw {
            case 0: return .messageEmoji
            case 1: return .recentEmoji
            default: return .emojiCategory(categoryIndex: raw - 2)
            }
        case (true, false):
            // Message emoji and then categories
            switch raw {
            case 0: return .messageEmoji
            default: return .emojiCategory(categoryIndex: raw - 1)
            }
        case (false, true):
            // Recents and then categories
            switch raw {
            case 0: return .recentEmoji
            default: return .emojiCategory(categoryIndex: raw - 1)
            }
        case (false, false):
            return .emojiCategory(categoryIndex: raw)
        }
    }

    private func rawSection(from section: EmojiPickerSection) -> Int {
        switch (hasMessageEmoji, hasRecentEmoji) {
        case (true, true):
            // Message emoji, then recents, then categories.
            switch section {
            case .messageEmoji: return 0
            case .recentEmoji: return 1
            case .emojiCategory(let categoryIndex): return categoryIndex + 2
            }
        case (true, false):
            // Message emoji and then categories
            switch section {
            case .messageEmoji: return 0
            case .recentEmoji: return 0
            case .emojiCategory(let categoryIndex): return categoryIndex + 1
            }
        case (false, true):
            // Recents and then categories
            switch section {
            case .messageEmoji: return 0
            case .recentEmoji: return 0
            case .emojiCategory(let categoryIndex): return categoryIndex + 1
            }
        case (false, false):
            switch section {
            case .messageEmoji: return 0
            case .recentEmoji: return 0
            case .emojiCategory(let categoryIndex): return categoryIndex
            }
        }
    }

    func emojiForSection(_ section: Int) -> [EmojiWithSkinTones] {
        switch self.section(raw: section) {
        case .messageEmoji:
            return messageEmoji
        case .recentEmoji:
            return Array(recentEmoji[0..<min(maxRecentEmoji, recentEmoji.count)])
        case .emojiCategory(let categoryIndex):
            guard let category = Emoji.Category.allCases[safe: categoryIndex] else {
                owsFailDebug("Unexpectedly missing category for section \(section)")
                return []
            }

            guard let categoryEmoji = allSendableEmojiByCategory[category] else {
                owsFailDebug("Unexpectedly missing emoji for category \(category)")
                return []
            }

            return categoryEmoji
        }
    }

    func emojiForIndexPath(_ indexPath: IndexPath) -> EmojiWithSkinTones? {
        return isSearching ? emojiSearchResults[safe: indexPath.row] : emojiForSection(indexPath.section)[safe: indexPath.row]
    }

    func nameForSection(_ section: Int) -> String? {
        switch self.section(raw: section) {
        case .messageEmoji:
            return OWSLocalizedString(
                "EMOJI_CATEGORY_ON_MESSAGE_NAME",
                comment: "The name for the emoji section for emojis already used on the message"
            )
        case .recentEmoji:
            return OWSLocalizedString(
                "EMOJI_CATEGORY_RECENTS_NAME",
                comment: "The name for the emoji category 'Recents'"
            )
        case .emojiCategory(let categoryIndex):
            guard let category = Emoji.Category.allCases[safe: categoryIndex] else {
                owsFailDebug("Unexpectedly missing category for section \(section)")
                return nil
            }

            return category.localizedName
        }
    }

    func recordRecentEmoji(_ emoji: EmojiWithSkinTones, transaction: DBWriteTransaction) {
        guard recentEmoji.first != emoji else { return }
        guard emoji.isNormalized else {
            recordRecentEmoji(emoji.normalized, transaction: transaction)
            return
        }

        var newRecentEmoji = recentEmoji

        // Remove any existing entries for this emoji
        newRecentEmoji.removeAll { emoji == $0 }
        // Insert the selected emoji at the start of the list
        newRecentEmoji.insert(emoji, at: 0)
        // Truncate the recent emoji list to a maximum of 50 stored
        newRecentEmoji = Array(newRecentEmoji[0..<min(50, newRecentEmoji.count)])

        EmojiPickerCollectionView.keyValueStore.setObject(
            newRecentEmoji.map { $0.rawValue },
            key: EmojiPickerCollectionView.recentEmojiKey,
            transaction: transaction
        )
    }

    var lowestVisibleSection = 0
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        currentSkinTonePicker?.dismiss()
        currentSkinTonePicker = nil

        let newLowestVisibleSection = indexPathsForVisibleItems.reduce(into: Set<Int>()) { $0.insert($1.section) }.min() ?? 0

        guard scrollingToSection == nil || newLowestVisibleSection == self.rawSection(from: scrollingToSection!) else { return }

        scrollingToSection = nil

        if lowestVisibleSection != newLowestVisibleSection {
            pickerDelegate?.emojiPicker(self, didScrollToSection: self.section(raw: newLowestVisibleSection))
            lowestVisibleSection = newLowestVisibleSection
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        pickerDelegate?.emojiPickerWillBeginDragging(self)
    }

    // MARK: - Search

    func searchWithText(_ searchText: String?) {
        emojiSearchResults = searchResults(searchText)
        reloadData()
    }

    private func searchResults(_ searchText: String?) -> [EmojiWithSkinTones] {
        guard let searchText = searchText?.stripped else {
            return []
        }

        if
            searchText.count == 1,
            let searchEmoji = EmojiWithSkinTones(rawValue: searchText)
        {
            return [searchEmoji]
        }

        // Anchored matches are emoji that have a term that starts with the
        // search text. Unanchored matches are emoji that have a term that
        // contains the search text elsewhere.
        let initialResult = (anchoredMatches: [EmojiWithSkinTones](), unanchoredMatches: [EmojiWithSkinTones]())
        let result = allSendableEmoji.reduce(into: initialResult) { partialResult, emoji in
            let terms = emojiSearchIndex?[emoji.baseEmoji.rawValue] ?? [emoji.baseEmoji.name]

            var unanchoredMatch = false
            for term in terms {
                if let range = term.range(of: searchText, options: [.caseInsensitive]) {
                    if range.lowerBound == term.startIndex {
                        // Anchored match
                        if range.upperBound == term.endIndex {
                            // Exact match. Put very first
                            partialResult.anchoredMatches.insert(emoji, at: 0)
                        } else {
                            partialResult.anchoredMatches.append(emoji)
                        }
                        return
                    }
                    unanchoredMatch = true
                    // Don't break here to continue to check for anchored matches
                }
            }

            if unanchoredMatch {
                partialResult.unanchoredMatches.append(emoji)
            }
        }

        return result.anchoredMatches + result.unanchoredMatches
    }

    @objc
    private func emojiSearchManifestUpdated(notification: Notification) {
        emojiSearchLocalization = EmojiSearchIndex.searchIndexLocalizationForLocale(NSLocale.current.identifier)
        if let emojiSearchLocalization = emojiSearchLocalization {
            emojiSearchIndex = EmojiSearchIndex.emojiSearchIndex(for: emojiSearchLocalization, shouldFetch: false)
        }
    }

    @objc
    private func emojiSearchIndexUpdated(notification: Notification) {
        if let emojiSearchLocalization = emojiSearchLocalization {
            emojiSearchIndex = EmojiSearchIndex.emojiSearchIndex(for: emojiSearchLocalization, shouldFetch: false)
        }
    }

    var scrollingToSection: EmojiPickerSection?
    func scrollToSectionHeader(_ section: EmojiPickerSection, animated: Bool) {
        guard let attributes = layoutAttributesForSupplementaryElement(
            ofKind: UICollectionView.elementKindSectionHeader,
            at: IndexPath(item: 0, section: self.rawSection(from: section))
        ) else { return }
        scrollingToSection = section
        setContentOffset(CGPoint(x: 0, y: (attributes.frame.minY - contentInset.top)), animated: animated)
    }

    private weak var currentSkinTonePicker: EmojiSkinTonePicker?

    @objc
    private func handleLongPress(sender: UILongPressGestureRecognizer) {

        switch sender.state {
        case .began:
            let point = sender.location(in: self)
            guard let indexPath = indexPathForItem(at: point) else { return }
            guard let emoji = emojiForIndexPath(indexPath) else { return }
            guard let cell = cellForItem(at: indexPath) else { return }

            currentSkinTonePicker?.dismiss()
            currentSkinTonePicker = EmojiSkinTonePicker.present(referenceView: cell, emoji: emoji) { [weak self] emoji in
                guard let self = self else { return }

                if let emoji = emoji {
                    SSKEnvironment.shared.databaseStorageRef.asyncWrite { transaction in
                        self.recordRecentEmoji(emoji, transaction: transaction)
                        emoji.baseEmoji.setPreferredSkinTones(emoji.skinTones, transaction: transaction)
                    }

                    self.pickerDelegate?.emojiPicker(self, didSelectEmoji: emoji)
                }

                self.currentSkinTonePicker?.dismiss()
                self.currentSkinTonePicker = nil
            }
        case .changed:
            currentSkinTonePicker?.didChangeLongPress(sender)
        case .ended:
            currentSkinTonePicker?.didEndLongPress(sender)
        default:
            break
        }
    }

    @objc
    private func dismissSkinTonePicker() {
        currentSkinTonePicker?.dismiss()
        currentSkinTonePicker = nil
    }
}

extension EmojiPickerCollectionView: UIGestureRecognizerDelegate {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == tapGestureRecognizer {
            return currentSkinTonePicker != nil
        }

        return true
    }
}

extension EmojiPickerCollectionView: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let emoji = emojiForIndexPath(indexPath) else {
            return owsFailDebug("Missing emoji for indexPath \(indexPath)")
        }

        SSKEnvironment.shared.databaseStorageRef.asyncWrite { transaction in
            self.recordRecentEmoji(emoji, transaction: transaction)
            emoji.baseEmoji.setPreferredSkinTones(emoji.skinTones, transaction: transaction)
        }

        pickerDelegate?.emojiPicker(self, didSelectEmoji: emoji)
    }
}

extension EmojiPickerCollectionView: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return isSearching ? emojiSearchResults.count : emojiForSection(section).count
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        guard !isSearching else { return 1 }
        var numSections = 0
        if hasMessageEmoji { numSections += 1 }
        if hasRecentEmoji { numSections += 1 }
        numSections += Emoji.Category.allCases.count
        return numSections
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = dequeueReusableCell(withReuseIdentifier: EmojiCell.reuseIdentifier, for: indexPath)

        guard let emojiCell = cell as? EmojiCell else {
            owsFailDebug("unexpected cell type")
            return cell
        }

        guard let emoji = emojiForIndexPath(indexPath) else {
            owsFailDebug("unexpected indexPath")
            return cell
        }

        emojiCell.configure(emoji: emoji)

        return cell
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {

        let supplementaryView = dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: EmojiSectionHeader.reuseIdentifier,
            for: indexPath
        )

        guard let sectionHeader = supplementaryView as? EmojiSectionHeader else {
            owsFailDebug("unexpected supplementary view type")
            return supplementaryView
        }

        sectionHeader.label.text = nameForSection(indexPath.section)

        return sectionHeader
    }
}

extension EmojiPickerCollectionView: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        referenceSizeForHeaderInSection section: Int) -> CGSize {
        guard !isSearching else {
            return CGSize.zero
        }

        let measureCell = EmojiSectionHeader(forceDarkTheme: self.forceDarkTheme)
        measureCell.label.text = nameForSection(section)
        return measureCell.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}

final private class EmojiCell: UICollectionViewCell {
    static let reuseIdentifier = "EmojiCell"

    let emojiLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .clear

        emojiLabel.font = .boldSystemFont(ofSize: 32)
        contentView.addSubview(emojiLabel)
        emojiLabel.autoPinEdgesToSuperviewEdges()

        // For whatever reason, some emoji glyphs occasionally have different typographic widths on certain devices
        // e.g. 👩‍🦰: 36x38.19, 👱‍♀️: 40x38. (See: commit message for more info)
        // To workaround this, we can clip the label instead of truncating. It appears to only clip the additional
        // typographic space. In either case, it's better than truncating and seeing an ellipsis.
        emojiLabel.lineBreakMode = .byClipping
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(emoji: EmojiWithSkinTones) {
        emojiLabel.text = emoji.rawValue
    }
}

final private class EmojiSectionHeader: UICollectionReusableView {
    static let reuseIdentifier = "EmojiSectionHeader"

    let label = UILabel()

    private override init(frame: CGRect) {
        super.init(frame: frame)

        layoutMargins = UIEdgeInsets(
            top: 16,
            leading: EmojiPickerCollectionView.margins,
            bottom: 6,
            trailing: EmojiPickerCollectionView.margins
        )

        label.font = UIFont.dynamicTypeFootnoteClamped.semibold()
        addSubview(label)
        label.autoPinEdgesToSuperviewMargins()
        label.setCompressionResistanceHigh()
    }

    convenience init(forceDarkTheme: Bool = false) {
        self.init(frame: .zero)
        label.textColor = forceDarkTheme ? Theme.darkThemeSecondaryTextAndIconColor : Theme.secondaryTextAndIconColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        var labelSize = label.sizeThatFits(size)
        labelSize.width += layoutMargins.left + layoutMargins.right
        labelSize.height += layoutMargins.top + layoutMargins.bottom
        return labelSize
    }
}

// URL handling
final private class EmojiSearchIndex: NSObject {

    public static let EmojiSearchManifestFetchedNotification = Notification.Name("EmojiSearchManifestFetchedNotification")
    public static let EmojiSearchIndexFetchedNotification = Notification.Name("EmojiSearchIndexFetchedNotification")

    private static let emojiSearchIndexKVS = KeyValueStore(collection: "EmojiSearchIndexKeyValueStore")
    private static let emojiSearchIndexVersionKey = "emojiSearchIndexVersionKey"
    private static let emojiSearchIndexAvailableLocalizationsKey = "emojiSearchIndexAvailableLocalizationsKey"

    private static let remoteManifestURL = URL(string: "/dynamic/android/emoji/search/manifest.json")!
    private static let remoteSearchFormat = "/static/android/emoji/search/%d/%@.json"

    public class func updateManifestIfNeeded() {
        var searchIndexVersion: Int = 0
        var searchIndexLocalizations: [String] = []
        (searchIndexVersion, searchIndexLocalizations) = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            let version = self.emojiSearchIndexKVS.getInt(emojiSearchIndexVersionKey, transaction: transaction) ?? 0
            let locs = self.emojiSearchIndexKVS.getStringArray(emojiSearchIndexAvailableLocalizationsKey, transaction: transaction) ?? []
            return (version, locs)
        }

        let urlSession = SSKEnvironment.shared.signalServiceRef.urlSessionForUpdates()
        Task {
            do {
                let response = try await urlSession.performRequest(self.remoteManifestURL.absoluteString, method: .get)
                guard response.responseStatusCode == 200 else {
                    throw OWSAssertionError("Bad response code for emoji manifest fetch")
                }

                guard let json = response.responseBodyJson as? [String: Any] else {
                    throw OWSAssertionError("Unable to generate JSON for emoji manifest from response body.")
                }

                guard let parser = ParamParser(responseObject: json) else {
                    throw OWSAssertionError("Unable to parse emoji manifest from response body.")
                }

                let remoteVersion: Int = try parser.required(key: "version")
                let remoteLocalizations: [String] = try parser.required(key: "languages")
                if remoteVersion != searchIndexVersion {
                    Logger.info("[Emoji Search] Invalidating search index, old version \(searchIndexVersion), new version \(remoteVersion)")
                    await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                        self.invalidateSearchIndex(
                            newVersion: remoteVersion,
                            localizationsToInvalidate: searchIndexLocalizations,
                            newLocalizations: remoteLocalizations,
                            tx: tx
                        )
                    }
                    let localization = self.searchIndexLocalizationForLocale(NSLocale.current.identifier, searchIndexManifest: remoteLocalizations)
                    if let localization = localization {
                        self.fetchEmojiSearchIndex(for: localization, version: remoteVersion)
                    }
                    NotificationCenter.default.postOnMainThread(name: self.EmojiSearchManifestFetchedNotification, object: nil)
                }
            } catch {
                owsFailDebug("Failed to download manifest \(error)")
            }
        }
    }

    public static func searchIndexLocalizationForLocale(_ locale: String, searchIndexManifest: [String]? = nil) -> String? {
        var manifest = searchIndexManifest
        if manifest == nil {
            manifest = SSKEnvironment.shared.databaseStorageRef.read { transaction in
                return self.emojiSearchIndexKVS.getStringArray(emojiSearchIndexAvailableLocalizationsKey, transaction: transaction) ?? []
            }
        }

        guard let manifest = manifest else {
            Logger.info("[Emoji Search] Manifest not yet downloaded")
            return nil
        }

        // We have a specific locale for this
        if manifest.contains(locale) {
            return locale
        }

        // Look for a generic top level
        let localizationComponents = locale.components(separatedBy: "_")
        if localizationComponents.count > 1, let firstComponent = localizationComponents.first {
            if manifest.contains(firstComponent) {
                return firstComponent
            }
        }
        return nil
    }

    public static func emojiSearchIndex(for localization: String, shouldFetch: Bool) -> [String: [String]]? {
        let index = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            return self.emojiSearchIndexKVS.getObject(
                localization,
                ofClasses: [NSDictionary.self, NSArray.self, NSString.self],
                transaction: transaction
            ) as? [String: [String]]
        }

        if shouldFetch && index == nil {
            Logger.debug("Kicking off fetch for localization \(localization)")
            self.fetchEmojiSearchIndex(for: localization)
        }

        return index
    }

    private static func invalidateSearchIndex(
        newVersion: Int,
        localizationsToInvalidate: [String],
        newLocalizations: [String],
        tx: DBWriteTransaction
    ) {
        for localization in localizationsToInvalidate {
            emojiSearchIndexKVS.removeValue(forKey: localization, transaction: tx)
        }
        emojiSearchIndexKVS.setObject(newLocalizations, key: emojiSearchIndexAvailableLocalizationsKey, transaction: tx)
        emojiSearchIndexKVS.setInt(newVersion, key: emojiSearchIndexVersionKey, transaction: tx)
    }

    private static func fetchEmojiSearchIndex(for localization: String, version: Int? = nil) {

        var searchIndexVersion = version
        if searchIndexVersion == nil {
            searchIndexVersion = SSKEnvironment.shared.databaseStorageRef.read { transaction in
                return self.emojiSearchIndexKVS.getInt(emojiSearchIndexVersionKey, transaction: transaction) ?? 0
            }
        }

        guard let searchIndexVersion = searchIndexVersion else {
            owsFailDebug("No local emoji index version, manifest must be updated first")
            return
        }

        let urlSession = SSKEnvironment.shared.signalServiceRef.urlSessionForUpdates()
        let request = String(format: remoteSearchFormat, searchIndexVersion, localization)
        Task {
            do {
                let response = try await urlSession.performRequest(request, method: .get)
                guard response.responseStatusCode == 200 else {
                    throw OWSAssertionError("Bad response code for emoji index fetch")
                }

                guard let json = response.responseBodyJson as? [[String: Any]] else {
                    throw OWSAssertionError("Unable to generate JSON for emoji index from response body.")
                }

                let index = self.buildSearchIndexMap(for: json)
                await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
                    self.emojiSearchIndexKVS.setObject(index, key: localization, transaction: transaction)
                }

                NotificationCenter.default.postOnMainThread(name: self.EmojiSearchIndexFetchedNotification, object: nil)

            } catch {
                owsFailDebug("Failed to download manifest \(error)")
            }
        }
    }

    private static func buildSearchIndexMap(for responseArray: [[String: Any]]) -> [String: [String]] {
        var index: [String: [String]] = [:]

        for response in responseArray {
            let emoji: String? = response["emoji"] as? String
            let tags: [String]? = response["tags"] as? [String]
            if let emoji = emoji, let tags = tags {
                index[emoji] = tags
            }
        }

        return index
    }
}
