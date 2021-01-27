
public enum IPv4 {
    
    public static func toInt(_ ip: String) -> Int {
        let octets: [Int] = ip.split(separator: ".").map { Int($0)! }
        var result: Int = 0
        for i in stride(from: 3, through: 0, by: -1) {
            result += octets[ 3 - i ] << (i * 8)
        }
        return result
    }
}
