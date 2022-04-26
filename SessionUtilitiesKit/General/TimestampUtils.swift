
public final class TimestampUtils {
    
    public static func isWithinOneMinute(timestamp: UInt64) -> Bool {
        Date().timeIntervalSince(NSDate.ows_date(withMillisecondsSince1970: timestamp)) <= 60
    }
    
}
