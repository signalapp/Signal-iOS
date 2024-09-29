//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import libPhoneNumber_iOS

public class PhoneNumberUtilSwiftValues {
    fileprivate let nbPhoneNumberUtil = NBPhoneNumberUtil()
    fileprivate let countryCodesFromCallingCodeCache = AtomicDictionary<String, [String]>([:], lock: .init())
    fileprivate let parsedPhoneNumberCache = LRUCache<String, NBPhoneNumber>(
        maxSize: 256,
        nseMaxSize: 0,
        shouldEvacuateInBackground: false
    )
    fileprivate let nationalPrefixTransformRuleCache = AtomicDictionary<String, String?>([:], lock: .init())
    fileprivate let phoneNumberCountryCodeCache = AtomicDictionary<String, String?>([:], lock: .init())
}

// MARK: -

@objc
public class PhoneNumberUtil: NSObject {
    public let swiftValues: PhoneNumberUtilSwiftValues

    public init(swiftValues: PhoneNumberUtilSwiftValues) {
        self.swiftValues = swiftValues

        super.init()

        SwiftSingletons.register(self)
    }

    // TODO: This function should use characters instead of UTF16 code units, but it's been translated as-is from ObjC for now.
    /// Translates cursor position from a given offset to another offset between a source and target string.
    ///
    /// - Parameters:
    ///   - offset: UTF-16 code unit offset into the source string
    /// - Returns:
    ///   a UTF-16 code unit offset into the target string
    public static func translateCursorPosition(_ offset: UInt, from source: String, to target: String, stickingRightward preferHigh: Bool) -> UInt {
        owsAssertDebug(offset <= source.utf16.count)
        if offset > source.utf16.count {
            return 0
        }

        let n = source.utf16.count
        let m = target.utf16.count

        var moves = Array(repeating: Array(repeating: Int(0), count: m + 1), count: n + 1)
        do {
            // Wagner-Fischer algorithm for computing edit distance, with a tweaks:
            // - Tracks best moves at each location, to allow reconstruction of edit path
            // - Does not allow substitutions
            // - Over-values digits relative to other characters, so they're "harder" to delete or insert
            let digitValue: UInt = 10
            var scores = Array(repeating: Array(repeating: UInt(0), count: m + 1), count: n + 1)
            moves[0][0] = 0  // (match) move up and left
            scores[0][0] = 0
            if n > 0 {
                for i in 1...n {
                    scores[i][0] = UInt(i)
                    moves[i][0] = -1  // (deletion) move left
                }
            }
            if m > 0 {
                for j in 1...m {
                    scores[0][j] = UInt(j)
                    moves[0][j] = +1  // (insertion) move up
                }
            }

            if n > 0 && m > 0 {
                let digits = CharacterSet.decimalDigits as NSCharacterSet
                for i in 1...n {
                    let c1 = source.utf16[source.utf16.index(source.utf16.startIndex, offsetBy: i - 1)]
                    let isDigit1 = digits.characterIsMember(c1)
                    for j in 1...m {
                        let c2 = target.utf16[target.utf16.index(target.utf16.startIndex, offsetBy: j - 1)]
                        let isDigit2 = digits.characterIsMember(c2)
                        if c1 == c2 {
                            scores[i][j] = scores[i - 1][j - 1]
                            moves[i][j] = 0  // move up-and-left
                        } else {
                            let del = scores[i - 1][j] + (isDigit1 ? digitValue : UInt(1))
                            let ins = scores[i][j - 1] + (isDigit2 ? digitValue : UInt(1))
                            let isDel = del < ins
                            scores[i][j] = isDel ? del : ins
                            moves[i][j] = isDel ? -1 : +1
                        }
                    }
                }
            }
        }

        // Backtrack to find desired corresponding offset
        var i = n
        var j = m
        while true {
            if i == offset && preferHigh {
                return UInt(j)
            }
            while moves[i][j] == +1 {
                j -= 1  // zip upward
            }
            if i == offset {
                return UInt(j)  // late exit
            }
            if moves[i][j] == 0 {
                j -= 1
            }
            i -= 1
        }
    }
}

extension PhoneNumberUtil {
    // country code -> calling code
    public func callingCode(fromCountryCode countryCode: String) -> String? {
        guard let countryCode = countryCode.nilIfEmpty else {
            return "+0"
        }

        if countryCode == "AQ" {
            // Antarctica
            return "+672"
        } else if countryCode == "BV" {
            // Bouvet Island
            return "+55"
        } else if countryCode == "IC" {
            // Canary Islands
            return "+34"
        } else if countryCode == "EA" {
            // Ceuta & Melilla
            return "+34"
        } else if countryCode == "CP" {
            // Clipperton Island
            //
            // This country code should be filtered - it does not appear to have a calling code.
            return nil
        } else if countryCode == "DG" {
            // Diego Garcia
            return "+246"
        } else if countryCode == "TF" {
            // French Southern Territories
            return "+262"
        } else if countryCode == "HM" {
            // Heard & McDonald Islands
            return "+672"
        } else if countryCode == "XK" {
            // Kosovo
            return "+383"
        } else if countryCode == "PN" {
            // Pitcairn Islands
            return "+64"
        } else if countryCode == "GS" {
            // So. Georgia & So. Sandwich Isl.
            return "+500"
        } else if countryCode == "UM" {
            // U.S. Outlying Islands
            return "+1"
        }

        let callingCode = getCallingCode(forRegion: countryCode)
        return PhoneNumber.countryCodePrefix + "\(callingCode.intValue)"
    }

    @objc
    public static func defaultCountryCode() -> String {
        return Locale.current.regionCode ?? "US"
    }

    // Returns a list of country codes for a calling code in descending
    // order of population.
    public func countryCodes(fromCallingCode callingCode: String) -> [String] {
        guard let callingCode = callingCode.nilIfEmpty else {
            return []
        }
        if let cachedValue = swiftValues.countryCodesFromCallingCodeCache[callingCode] {
            return cachedValue
        }
        let countryCodes: [String] = Self.countryCodesSortedByPopulationDescending.compactMap { (countryCode: String) -> String? in
            let callingCodeForCountryCode: String? = self.callingCode(fromCountryCode: countryCode)
            guard callingCode == callingCodeForCountryCode else {
                return nil
            }
            return countryCode
        }
        swiftValues.countryCodesFromCallingCodeCache[callingCode] = countryCodes
        return countryCodes
    }

    @objc
    public func format(_ phoneNumber: NBPhoneNumber, numberFormat: NBEPhoneNumberFormat) throws -> String {
        try swiftValues.nbPhoneNumberUtil.format(phoneNumber, numberFormat: numberFormat)
    }

    @objc
    public func parse(_ numberToParse: String, defaultRegion: String) throws -> NBPhoneNumber {
        let hashKey = "numberToParse:\(numberToParse), defaultRegion:\(defaultRegion)"
        if let cachedValue = swiftValues.parsedPhoneNumberCache[hashKey] {
            return cachedValue
        }
        let result = try swiftValues.nbPhoneNumberUtil.parse(numberToParse, defaultRegion: defaultRegion)
        swiftValues.parsedPhoneNumberCache[hashKey] = result
        return result
    }

    public func examplePhoneNumber(forCountryCode countryCode: String) -> String? {
        // Signal users are very likely using mobile devices, so prefer that kind of example.
        do {
            func findExamplePhoneNumber() -> NBPhoneNumber? {
                let types: [NBEPhoneNumberType] = [.MOBILE, .FIXED_LINE_OR_MOBILE]
                for type in types {
                    let phoneNumber = PhoneNumberUtil.getExampleNumber(
                        forType: countryCode,
                        type: type,
                        nbPhoneNumberUtil: swiftValues.nbPhoneNumberUtil
                    )
                    if let phoneNumber {
                        return phoneNumber
                    }
                }
                return nil
            }
            guard let nbPhoneNumber = findExamplePhoneNumber() else {
                owsFailDebug("Could not find example phone number for: \(countryCode)")
                return nil
            }
            return try swiftValues.nbPhoneNumberUtil.format(nbPhoneNumber, numberFormat: .E164)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    public func isPossibleNumber(_ number: NBPhoneNumber) -> Bool {
        return swiftValues.nbPhoneNumberUtil.isPossibleNumber(number)
    }

    @objc
    public func getRegionCodeForCountryCode(_ countryCallingCode: NSNumber) -> String {
        return swiftValues.nbPhoneNumberUtil.getRegionCode(forCountryCode: countryCallingCode)
    }

    @objc
    public func isValidNumber(_ number: NBPhoneNumber) -> Bool {
        return swiftValues.nbPhoneNumberUtil.isValidNumber(number)
    }

    public func getCallingCode(forRegion regionCode: String) -> NSNumber {
        return swiftValues.nbPhoneNumberUtil.getCountryCode(forRegion: regionCode)
    }

    @objc
    public func nationalNumber(for phoneNumber: PhoneNumber) -> String {
        return swiftValues.nbPhoneNumberUtil.getNationalSignificantNumber(phoneNumber.nbPhoneNumber)
    }

    @objc
    public func formattedNationalNumber(for phoneNumber: PhoneNumber) -> String? {
        return try? format(phoneNumber.nbPhoneNumber, numberFormat: .NATIONAL)
    }

    /// Returns the most likely country code for a calling code based on population.
    /// If no country codes are found, returns the empty string.
    @objc
    public func probableCountryCode(forCallingCode callingCode: String) -> String {
        return countryCodes(fromCallingCode: callingCode).first ?? ""
    }

    private class func does(_ string: String, matchQuery query: String) -> Bool {
        let searchOptions: String.CompareOptions = [.caseInsensitive, .anchored]

        let stringTokens = string.components(separatedBy: .whitespaces)
        let queryTokens = query.components(separatedBy: .whitespaces)

        return queryTokens.allSatisfy { queryToken in
            if queryToken.isEmpty {
                return true
            }
            return stringTokens.contains { stringToken in
                stringToken.range(of: queryToken, options: searchOptions) != nil
            }
        }
    }

    /// Get country codes from a search term.
    @objc
    public func countryCodes(forSearchTerm searchTerm: String?) -> [String] {
        let cleanedSearch = (searchTerm ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let codes = NSLocale.isoCountryCodes.filter { countryCode in
            guard
                let callingCode = callingCode(fromCountryCode: countryCode),
                !callingCode.isEmpty,
                callingCode != "+0"
            else {
                return false
            }
            let countryName = Self.countryName(fromCountryCode: countryCode)
            return (
                cleanedSearch.isEmpty ||
                Self.does(countryName, matchQuery: cleanedSearch) ||
                Self.does(countryCode, matchQuery: cleanedSearch) ||
                callingCode.contains(cleanedSearch)
            )
        }

        return codes.sorted { lhs, rhs in
            let lhsCountry = Self.countryName(fromCountryCode: lhs)
            let rhsCountry = Self.countryName(fromCountryCode: rhs)
            return lhsCountry.localizedCaseInsensitiveCompare(rhsCountry) == .orderedAscending
        }
    }

    /// Convert country code to country name.
    @objc
    public class func countryName(fromCountryCode countryCode: String) -> String {
        lazy var unknownValue =  OWSLocalizedString(
            "UNKNOWN_VALUE",
            comment: "Indicates an unknown or unrecognizable value."
        )

        if countryCode.isEmpty {
            return unknownValue
        }

        return Locale.current.localizedString(forRegionCode: countryCode)?.nilIfEmpty ?? unknownValue
    }

    private func parsePhoneNumber(_ numberToParse: String, regionCode: String) -> PhoneNumber? {
        do {
            let phoneNumber = try parse(numberToParse, defaultRegion: regionCode)
            guard isPossibleNumber(phoneNumber) else {
                return nil
            }
            let phoneNumberE164 = try format(phoneNumber, numberFormat: .E164)
            return PhoneNumber(nbPhoneNumber: phoneNumber, e164: phoneNumberE164)
        } catch {
            return nil
        }
    }

    @objc
    public func parsePhoneNumber(userSpecifiedText: String) -> PhoneNumber? {
        if userSpecifiedText.isEmpty {
            return nil
        }
        let sanitizedText = userSpecifiedText.filteredAsE164
        return parsePhoneNumber(sanitizedText, regionCode: Self.defaultCountryCode())
    }

    /// `text` may omit the calling code or duplicate the value in `callingCode`.
    public func parsePhoneNumber(userSpecifiedText: String, callingCode: String) -> PhoneNumber? {
        if userSpecifiedText.isEmpty {
            return nil
        }
        let regionCode = getRegionCodeForCountryCode(NSNumber(value: (callingCode as NSString).integerValue))
        if regionCode == NB_UNKNOWN_REGION {
            return parsePhoneNumber(userSpecifiedText: callingCode.appending(userSpecifiedText))
        }
        var sanitizedText = userSpecifiedText.filteredAsE164
        if sanitizedText.hasPrefix("+") {
            sanitizedText = String(sanitizedText.dropFirst())
        }
        return parsePhoneNumber(sanitizedText, regionCode: regionCode)
    }

    @objc
    public func parseE164(_ phoneNumberString: String) -> PhoneNumber? {
        guard let phoneNumber = E164(phoneNumberString) else {
            return nil
        }
        return parseE164(phoneNumber)
    }

    public func parseE164(_ phoneNumber: E164) -> PhoneNumber? {
        return parsePhoneNumber(phoneNumber.stringValue, regionCode: "ZZ")
    }

    @objc
    public func parsePhoneNumbers(userSpecifiedText: String, localPhoneNumber: String?) -> [PhoneNumber] {
        var results = parsePhoneNumbers(normalizedText: userSpecifiedText, localPhoneNumber: localPhoneNumber)

        // A handful of countries (Mexico, Argentina, etc.) require a "national"
        // prefix after their country calling code.
        //
        // It's a bit hacky, but we reconstruct these national prefixes from
        // libPhoneNumber's parsing logic. It's okay if we botch this a little. The
        // risk is that we end up with some misformatted numbers with extra
        // non-numeric regex syntax. These erroneously parsed numbers will never be
        // presented to the user, since they'll never survive the contacts
        // intersection.
        //
        // Try to apply a "national prefix" using the phone's region and using the
        // region that corresponds to the calling code for the local phone number.
        let countryCodes: [String] = [
            Self.defaultCountryCode(),
            localPhoneNumber.flatMap { countryCode(for: $0) },
        ].compacted().removingDuplicates(uniquingElementsBy: { $0 })

        for countryCode in countryCodes {
            guard let transformRule = nationalPrefixTransformRule(countryCode: countryCode) else {
                continue
            }
            guard transformRule.contains("$1") else {
                continue
            }
            let normalizedText = transformRule.replacingOccurrences(of: "$1", with: userSpecifiedText)
            guard !normalizedText.contains("$") else {
                continue
            }
            results.append(contentsOf: parsePhoneNumbers(
                normalizedText: normalizedText,
                localPhoneNumber: localPhoneNumber
            ))
        }

        return results
    }

    /// This will try to parse the input text as a phone number using the
    /// default region and the country code for this client's phone number.
    ///
    /// Order matters; better results will appear first.
    func parsePhoneNumbers(normalizedText: String, localPhoneNumber: String?) -> [PhoneNumber] {
        guard let text = normalizedText.filteredAsE164.nilIfEmpty else {
            return []
        }

        var results = [PhoneNumber]()
        var phoneNumbers = Set<String>()

        func tryParsing(_ text: String, countryCode: String) {
            guard let phoneNumber = parsePhoneNumber(text, regionCode: countryCode) else {
                return
            }
            guard phoneNumbers.insert(phoneNumber.e164).inserted else {
                return
            }
            results.append(phoneNumber)
        }

        let defaultCountryCode = Self.defaultCountryCode()

        tryParsing(text, countryCode: defaultCountryCode)

        if text.hasPrefix("+") {
            // If the text starts with "+", don't try prepending
            // anything else.
            return results
        }

        // Try just adding "+" and parsing it.
        tryParsing("+" + text, countryCode: defaultCountryCode)

        // Order matters; better results should appear first so prefer
        // matches with the same country code as this client's phone number.
        guard let localPhoneNumber else {
            owsFailDebug("localPhoneNumber is missing")
            return results
        }

        // Note that NBPhoneNumber uses "country code" to refer to what we call a
        // "calling code" (i.e. 44 in +44123123).  Within SSK we use "country code"
        // (and sometimes "region code") to refer to a country's ISO 2-letter code
        // (ISO 3166-1 alpha-2).
        guard let callingCodeForLocalNumber = parseE164(localPhoneNumber)?.getCallingCode() else {
            owsFailDebug("callingCodeForLocalNumber is missing")
            return results
        }

        let callingCodePrefix = "+\(callingCodeForLocalNumber)"

        tryParsing(callingCodePrefix + text, countryCode: defaultCountryCode)

        // Try to determine what the country code is for the local phone number and
        // also try parsing the phone number using that country code if it differs
        // from the device's region code.
        //
        // For example, a French person living in Italy might have an Italian phone
        // number but use French region/language for their phone. They're likely to
        // have both Italian and French contacts.
        let localCountryCode = probableCountryCode(forCallingCode: callingCodePrefix)
        if localCountryCode != defaultCountryCode {
            tryParsing(callingCodePrefix + text, countryCode: localCountryCode)
        }

        let phoneNumberWithAreaCodeIfMissing = Self.phoneNumberWithAreaCodeIfMissing(
            normalizedText: text,
            localCallingCode: callingCodeForLocalNumber,
            localPhoneNumber: localPhoneNumber
        )
        if let phoneNumberWithAreaCodeIfMissing {
            tryParsing(phoneNumberWithAreaCodeIfMissing, countryCode: localCountryCode)
        }

        return results
    }

    /// Adds the local user's area code to `normalizedText` if it doesn't have its own.
    private static func phoneNumberWithAreaCodeIfMissing(
        normalizedText: String,
        localCallingCode: NSNumber,
        localPhoneNumber: String
    ) -> String? {
        switch localCallingCode.intValue {
        case 1:
            return addMissingAreaCode(
                normalizedText: normalizedText,
                localCallingCode: localCallingCode,
                localPhoneNumber: localPhoneNumber,
                missingAreaCodeRegex: Self.missingUSAreaCodeRegex,
                areaCodeRegex: Self.usAreaCodeRegex
            )
        case 55:
            return addMissingAreaCode(
                normalizedText: normalizedText,
                localCallingCode: localCallingCode,
                localPhoneNumber: localPhoneNumber,
                missingAreaCodeRegex: Self.missingBRAreaCodeRegex,
                areaCodeRegex: Self.brAreaCodeRegex
            )
        default:
            return nil
        }
    }

    private static let missingUSAreaCodeRegex: NSRegularExpression = {
        return try! NSRegularExpression(pattern: #"^(\d{7})$"#)
    }()

    private static let usAreaCodeRegex: NSRegularExpression = {
        return try! NSRegularExpression(pattern: #"^\+1(\d{3})"#)
    }()

    private static let missingBRAreaCodeRegex: NSRegularExpression = {
        return try! NSRegularExpression(pattern: #"^(9?\d{8})$"#)
    }()

    private static let brAreaCodeRegex: NSRegularExpression = {
        return try! NSRegularExpression(pattern: #"^\+55(\d{2})9?\d{8}"#)
    }()

    private static func addMissingAreaCode(
        normalizedText: String,
        localCallingCode: NSNumber,
        localPhoneNumber: String,
        missingAreaCodeRegex: NSRegularExpression,
        areaCodeRegex: NSRegularExpression
    ) -> String? {
        let match = missingAreaCodeRegex.firstMatch(in: normalizedText, range: normalizedText.entireRange)
        if match == nil {
            return nil
        }
        let localAreaCodeNSRange = areaCodeRegex.matches(
            in: localPhoneNumber,
            range: NSRange(localPhoneNumber.startIndex..., in: localPhoneNumber)
        ).first?.range(at: 1)
        guard
            let localAreaCodeNSRange,
            let localAreaCodeRange = Range(localAreaCodeNSRange, in: localPhoneNumber)
        else {
            return nil
        }
        return "+\(localCallingCode)\(localPhoneNumber[localAreaCodeRange])\(normalizedText)"
    }

    private func nationalPrefixTransformRule(countryCode: String) -> String? {
        if let transformRule = swiftValues.nationalPrefixTransformRuleCache[countryCode] {
            return transformRule
        }
        let transformRule: String? = NBMetadataHelper().getMetadataForRegion(countryCode)?.nationalPrefixTransformRule
        swiftValues.nationalPrefixTransformRuleCache[countryCode] = transformRule
        return transformRule
    }

    private func countryCode(for phoneNumber: String) -> String? {
        if let countryCode = swiftValues.phoneNumberCountryCodeCache[phoneNumber] {
            return countryCode
        }
        let countryCode: String? = {
            guard let callingCode = parseE164(phoneNumber)?.getCallingCode() else {
                return nil
            }
            return probableCountryCode(forCallingCode: "+\(callingCode)").nilIfEmpty
        }()
        swiftValues.phoneNumberCountryCodeCache[phoneNumber] = countryCode
        return countryCode
    }

    private static let countryCodesSortedByPopulationDescending: [String] = [
        "CN", // 1330044000
        "IN", // 1173108018
        "US", // 310232863
        "ID", // 242968342
        "BR", // 201103330
        "PK", // 184404791
        "BD", // 156118464
        "NG", // 154000000
        "RU", // 140702000
        "JP", // 127288000
        "MX", // 112468855
        "PH", // 99900177
        "VN", // 89571130
        "ET", // 88013491
        "DE", // 81802257
        "EG", // 80471869
        "TR", // 77804122
        "IR", // 76923300
        "CD", // 70916439
        "TH", // 67089500
        "FR", // 64768389
        "GB", // 62348447
        "IT", // 60340328
        "MM", // 53414374
        "ZA", // 49000000
        "KR", // 48422644
        "CO", // 47790000
        "ES", // 46505963
        "UA", // 45415596
        "TZ", // 41892895
        "AR", // 41343201
        "KE", // 40046566
        "PL", // 38500000
        "SD", // 35000000
        "DZ", // 34586184
        "MA", // 33848242
        "CA", // 33679000
        "UG", // 33398682
        "PE", // 29907003
        "IQ", // 29671605
        "AF", // 29121286
        "NP", // 28951852
        "MY", // 28274729
        "UZ", // 27865738
        "VE", // 27223228
        "SA", // 25731776
        "GH", // 24339838
        "YE", // 23495361
        "KP", // 22912177
        "TW", // 22894384
        "SY", // 22198110
        "MZ", // 22061451
        "RO", // 21959278
        "AU", // 21515754
        "LK", // 21513990
        "MG", // 21281844
        "CI", // 21058798
        "CM", // 19294149
        "CL", // 16746491
        "NL", // 16645000
        "BF", // 16241811
        "NE", // 15878271
        "MW", // 15447500
        "KZ", // 15340000
        "EC", // 14790608
        "KH", // 14453680
        "ML", // 13796354
        "GT", // 13550440
        "ZM", // 13460305
        "AO", // 13068161
        "ZW", // 13061000
        "SN", // 12323252
        "CU", // 11423000
        "RW", // 11055976
        "GR", // 11000000
        "PT", // 10676000
        "TN", // 10589025
        "TD", // 10543464
        "CZ", // 10476000
        "BE", // 10403000
        "GN", // 10324025
        "SO", // 10112453
        "HU", // 9982000
        "BO", // 9947418
        "BI", // 9863117
        "SE", // 9828655
        "DO", // 9823821
        "BY", // 9685000
        "HT", // 9648924
        "BJ", // 9056010
        "AZ", // 8303512
        "SS", // 8260490
        "AT", // 8205000
        "HN", // 7989415
        "CH", // 7581000
        "TJ", // 7487489
        "IL", // 7353985
        "RS", // 7344847
        "BG", // 7148785
        "HK", // 6898686
        "TG", // 6587239
        "LY", // 6461454
        "JO", // 6407085
        "PY", // 6375830
        "LA", // 6368162
        "PG", // 6064515
        "SV", // 6052064
        "NI", // 5995928
        "ER", // 5792984
        "KG", // 5776500
        "DK", // 5484000
        "SK", // 5455000
        "SL", // 5245695
        "FI", // 5244000
        "NO", // 5009150
        "AE", // 4975593
        "TM", // 4940916
        "CF", // 4844927
        "SG", // 4701069
        "GE", // 4630000
        "IE", // 4622917
        "BA", // 4590000
        "CR", // 4516220
        "MD", // 4324000
        "HR", // 4284889
        "NZ", // 4252277
        "LB", // 4125247
        "PR", // 3916632
        "PS", // 3800000
        "LR", // 3685076
        "UY", // 3477000
        "PA", // 3410676
        "MR", // 3205060
        "MN", // 3086918
        "CG", // 3039126
        "AL", // 2986952
        "AM", // 2968000
        "OM", // 2967717
        "LT", // 2944459
        "JM", // 2847232
        "KW", // 2789132
        "LV", // 2217969
        "NA", // 2128471
        "MK", // 2062294
        "BW", // 2029307
        "SI", // 2007000
        "LS", // 1919552
        "XK", // 1800000
        "GM", // 1593256
        "GW", // 1565126
        "GA", // 1545255
        "SZ", // 1354051
        "TT", // 1328019
        "MU", // 1294104
        "EE", // 1291170
        "TL", // 1154625
        "CY", // 1102677
        "GQ", // 1014999
        "FJ", // 875983
        "QA", // 840926
        "RE", // 776948
        "KM", // 773407
        "GY", // 748486
        "DJ", // 740528
        "BH", // 738004
        "BT", // 699847
        "ME", // 666730
        "SB", // 559198
        "CV", // 508659
        "LU", // 497538
        "SR", // 492829
        "MO", // 449198
        "GP", // 443000
        "MQ", // 432900
        "MT", // 403000
        "MV", // 395650
        "BN", // 395027
        "BZ", // 314522
        "IS", // 308910
        "BS", // 301790
        "BB", // 285653
        "EH", // 273008
        "PF", // 270485
        "VU", // 221552
        "NC", // 216494
        "GF", // 195506
        "WS", // 192001
        "ST", // 175808
        "LC", // 160922
        "GU", // 159358
        "YT", // 159042
        "CW", // 141766
        "TO", // 122580
        "VI", // 108708
        "GD", // 107818
        "FM", // 107708
        "VC", // 104217
        "KI", // 92533
        "JE", // 90812
        "SC", // 88340
        "AG", // 86754
        "AD", // 84000
        "IM", // 75049
        "DM", // 72813
        "AW", // 71566
        "MH", // 65859
        "BM", // 65365
        "GG", // 65228
        "AS", // 57881
        "GL", // 56375
        "MP", // 53883
        "KN", // 51134
        "FO", // 48228
        "KY", // 44270
        "SX", // 37429
        "MF", // 35925
        "LI", // 35000
        "MC", // 32965
        "SM", // 31477
        "GI", // 27884
        "AX", // 26711
        "VG", // 21730
        "CK", // 21388
        "TC", // 20556
        "PW", // 19907
        "BQ", // 18012
        "WF", // 16025
        "AI", // 13254
        "TV", // 10472
        "NR", // 10065
        "MS", // 9341
        "BL", // 8450
        "SH", // 7460
        "PM", // 7012
        "IO", // 4000
        "FK", // 2638
        "SJ", // 2550
        "NU", // 2166
        "NF", // 1828
        "CX", // 1500
        "TK", // 1466
        "VA", // 921
        "CC", // 628
        "TF", // 140
        "PN", // 46
        "GS", // 30
        "AC", // 0
        "AQ", // 0
        "BV", // 0
        "CP", // 0
        "DG", // 0
        "EA", // 0
        "HM", // 0
        "IC", // 0
        "TA", // 0
        "UM", // 0
    ]

    private static func getExampleNumber(forType regionCode: String, type: NBEPhoneNumberType, nbPhoneNumberUtil: NBPhoneNumberUtil) -> NBPhoneNumber? {
        do {
            return try nbPhoneNumberUtil.getExampleNumber(forType: regionCode, type: type)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }
}
