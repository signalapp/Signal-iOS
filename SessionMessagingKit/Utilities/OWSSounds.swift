extension OWSSound {
    
    public func notificationSound(isQuiet: Bool) -> UNNotificationSound {
        guard let filename = OWSSounds.filename(for: self, quiet: isQuiet) else {
            owsFailDebug("filename was unexpectedly nil")
            return UNNotificationSound.default
        }
        return UNNotificationSound(named: UNNotificationSoundName(rawValue: filename))
    }
}
