//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

// A simple LRU cache bounded by the number of entries.
public class LRUCache<KeyType: Hashable & Equatable, ValueType> {

    private var cacheMap: [KeyType: ValueType] = [:]
    private var cacheOrder: [KeyType] = []
    private let maxSize: Int

    @objc
    public init(maxSize: Int) {
        self.maxSize = maxSize

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didReceiveMemoryWarning),
                                               name: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didEnterBackground),
                                               name: NSNotification.Name.OWSApplicationDidEnterBackground,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc func didEnterBackground() {
        clear()
    }

    @objc func didReceiveMemoryWarning() {
        clear()
    }

    private func updateCacheOrder(key: KeyType) {
        cacheOrder = cacheOrder.filter { $0 != key }
        cacheOrder.append(key)
    }

    public func get(key: KeyType) -> ValueType? {
        guard let value = cacheMap[key] else {
            // Miss
            return nil
        }

        // Hit
        updateCacheOrder(key: key)

        return value
    }

    public func set(key: KeyType, value: ValueType) {
        cacheMap[key] = value

        updateCacheOrder(key: key)

        while cacheOrder.count > maxSize {
            guard let staleKey = cacheOrder.first else {
                return
            }
            cacheOrder.removeFirst()
            cacheMap.removeValue(forKey: staleKey)
        }
    }

    @objc
    public func clear() {
        cacheMap.removeAll()
        cacheOrder.removeAll()
    }
}
