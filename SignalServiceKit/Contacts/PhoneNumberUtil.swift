//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import libPhoneNumber_iOS

// MARK: -

public class PhoneNumberUtil: NSObject {
    let nbMetadataHelper: NBMetadataHelper
    private let nbPhoneNumberUtil: NBPhoneNumberUtil
    private let parsedPhoneNumberCache = LRUCache<String, NBPhoneNumber>(
        maxSize: 256,
        nseMaxSize: 0,
        shouldEvacuateInBackground: false
    )
    private let nationalPrefixTransformRuleCache = AtomicDictionary<String, String?>([:], lock: .init())

    public override init() {
        self.nbMetadataHelper = NBMetadataHelper()
        self.nbPhoneNumberUtil = NBPhoneNumberUtil(metadataHelper: self.nbMetadataHelper)

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
    /// Returns calling codes for libPhoneNumber-unsupported country codes.
    ///
    /// These are country codes that NSLocale.isoCountryCodes contains but
    /// libPhoneNumber doesn't support. In every case, these countries share a
    /// calling code with a country that libPhoneNumber *does* support. We show
    /// these unsupported countries in the UI and convert them to a supported
    /// country when parsing the number.
    public static func callingCodeForUnsupportedCountryCode(_ countryCode: String) -> Int? {
        switch countryCode {
        case "AQ": /* Antarctica */ return 672
        case "BV": /* Bouvet Island */ return 55
        case "IC": /* Canary Islands */ return 34
        case "EA": /* Ceuta & Melilla */ return 34
        case "DG": /* Diego Garcia */ return 246
        case "TF": /* French Southern Territories */ return 262
        case "HM": /* Heard & McDonald Islands */ return 672
        case "PN": /* Pitcairn Islands */ return 64
        case "CQ": /* Sark */ return 44
        case "GS": /* So. Georgia & So. Sandwich Isl. */ return 500
        case "UM": /* U.S. Outlying Islands */ return 1
        default: return nil
        }
    }

    public func countryCodeForParsing(fromCountryCode countryCode: String) -> String {
        if let callingCode = Self.callingCodeForUnsupportedCountryCode(countryCode) {
            // Force unwrap is covered by unit tests.
            return getFilteredRegionCodeForCallingCode(callingCode)!
        }
        return countryCode
    }

    public static func defaultCountryCode() -> String {
        return Locale.current.regionCode ?? "US"
    }

    /// Computes the country code ("GB") for localNumber.
    ///
    /// If multiple countries share a calling code (e.g., the US and Canada
    /// share "1"), then we don't know which country to return for "1". If
    /// `defaultCountryCode` is one of them (e.g., "US" or "CA"), then we'll
    /// return `defaultCountryCode`.
    ///
    /// If localNumber can't be parsed, `defaultCountryCode` is returned.
    public func preferredCountryCode(forLocalNumber localNumber: String) -> String {
        // TODO: Determine countryCode precisely from the phone number.
        let defaultCountryCode = Self.defaultCountryCode()
        if let localCallingCode = parseE164(localNumber)?.getCallingCode() {
            if getCallingCode(forRegion: defaultCountryCode) == localCallingCode {
                return defaultCountryCode
            }
            let localCountryCode = getFilteredRegionCodeForCallingCode(localCallingCode)
            return localCountryCode ?? ""
        }
        return defaultCountryCode
    }

    private func format(_ phoneNumber: NBPhoneNumber, numberFormat: NBEPhoneNumberFormat) throws -> String {
        try nbPhoneNumberUtil.format(phoneNumber, numberFormat: numberFormat)
    }

    private func parse(_ numberToParse: String, defaultRegion: String) throws -> NBPhoneNumber {
        let hashKey = "numberToParse:\(numberToParse), defaultRegion:\(defaultRegion)"
        if let cachedValue = parsedPhoneNumberCache[hashKey] {
            return cachedValue
        }
        let result = try nbPhoneNumberUtil.parse(numberToParse, defaultRegion: defaultRegion)
        parsedPhoneNumberCache[hashKey] = result
        return result
    }

    public func exampleNationalNumber(forCountryCode countryCode: String) -> String? {
        // Signal users are very likely using mobile devices, so prefer that kind of example.
        do {
            func findExamplePhoneNumber() -> NBPhoneNumber? {
                let types: [NBEPhoneNumberType] = [.MOBILE, .FIXED_LINE_OR_MOBILE]
                for type in types {
                    do {
                        return try nbPhoneNumberUtil.getExampleNumber(forType: countryCode, type: type)
                    } catch {
                        owsFailDebug("Error: \(error)")
                    }
                }
                return nil
            }
            guard let nbPhoneNumber = findExamplePhoneNumber() else {
                owsFailDebug("Could not find example phone number for: \(countryCode)")
                return nil
            }
            return try nbPhoneNumberUtil.format(nbPhoneNumber, numberFormat: .NATIONAL)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    public func getRegionCodeForCallingCode(_ callingCode: Int) -> String {
        return nbPhoneNumberUtil.getRegionCode(forCountryCode: NSNumber(value: callingCode))
    }

    public func getFilteredRegionCodeForCallingCode(_ callingCode: Int) -> String? {
        let result = getRegionCodeForCallingCode(callingCode)
        if result == NB_UNKNOWN_REGION || result == NB_REGION_CODE_FOR_NON_GEO_ENTITY {
            return nil
        }
        return result
    }

    public func getCallingCode(forRegion regionCode: String) -> Int {
        return nbPhoneNumberUtil.getCountryCode(forRegion: regionCode).intValue
    }

    public func nationalNumber(for phoneNumber: PhoneNumber) -> String {
        return nbPhoneNumberUtil.getNationalSignificantNumber(phoneNumber.nbPhoneNumber)
    }

    public func formattedNationalNumber(for phoneNumber: PhoneNumber) -> String? {
        return try? format(phoneNumber.nbPhoneNumber, numberFormat: .NATIONAL)
    }

    /// Convert country code to country name.
    public static func countryName(fromCountryCode countryCode: String) -> String {
        lazy var unknownValue = OWSLocalizedString(
            "UNKNOWN_VALUE",
            comment: "Indicates an unknown or unrecognizable value."
        )

        if countryCode.isEmpty {
            return unknownValue
        }

        return Locale.current.localizedString(forRegionCode: countryCode)?.nilIfEmpty ?? unknownValue
    }

    private func _parsePhoneNumber(filteredValue: String, countryCode: String = defaultCountryCode()) -> PhoneNumber? {
        do {
            let phoneNumber = try parse(filteredValue, defaultRegion: countryCode)
            guard nbPhoneNumberUtil.isPossibleNumber(phoneNumber) else {
                return nil
            }
            let phoneNumberE164 = try format(phoneNumber, numberFormat: .E164)
            return PhoneNumber(nbPhoneNumber: phoneNumber, e164: phoneNumberE164)
        } catch {
            return nil
        }
    }

    public func parsePhoneNumber(userSpecifiedText: String) -> PhoneNumber? {
        return _parsePhoneNumber(filteredValue: userSpecifiedText.filteredAsE164)
    }

    public func parseE164(_ phoneNumberString: String) -> PhoneNumber? {
        guard let phoneNumber = E164(phoneNumberString) else {
            return nil
        }
        return parseE164(phoneNumber)
    }

    public func parseE164(_ phoneNumber: E164) -> PhoneNumber? {
        return _parsePhoneNumber(filteredValue: phoneNumber.stringValue)
    }

    public func parsePhoneNumber(countryCode: String, nationalNumber: String) -> PhoneNumber? {
        return _parsePhoneNumber(
            filteredValue: nationalNumber.filteredAsE164,
            countryCode: countryCodeForParsing(fromCountryCode: countryCode)
        )
    }

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
            localPhoneNumber
                .flatMap { parseE164($0)?.getCallingCode() }
                .flatMap { getFilteredRegionCodeForCallingCode($0) },
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

        func tryParsing(_ text: String) {
            guard let phoneNumber = _parsePhoneNumber(filteredValue: text) else {
                return
            }
            guard phoneNumbers.insert(phoneNumber.e164).inserted else {
                return
            }
            results.append(phoneNumber)
        }

        tryParsing(text)

        if text.hasPrefix("+") {
            // If the text starts with "+", don't try prepending
            // anything else.
            return results
        }

        // Try just adding "+" and parsing it.
        tryParsing("+" + text)

        // Order matters; better results should appear first so prefer
        // matches with the same country code as this client's phone number.
        guard let localPhoneNumber else {
            owsFailDebug("localPhoneNumber is missing")
            return results
        }

        guard let callingCodeForLocalNumber = parseE164(localPhoneNumber)?.getCallingCode() else {
            owsFailDebug("callingCodeForLocalNumber is missing")
            return results
        }

        // Parse the number as a national number with the same calling code as the
        // local user's phone number.
        //
        // For example, a French person living in Italy might have an Italian phone
        // number but use French region/language for their phone. They're likely to
        // have both Italian and French contacts (though I don't know why they
        // wouldn't prepend the correct international prefix...).
        let callingCodePrefix = "+\(callingCodeForLocalNumber)"
        tryParsing(callingCodePrefix + text)

        let phoneNumberWithAreaCodeIfMissing = Self.phoneNumberWithAreaCodeIfMissing(
            normalizedText: text,
            localCallingCode: callingCodeForLocalNumber,
            localPhoneNumber: localPhoneNumber
        )
        if let phoneNumberWithAreaCodeIfMissing {
            owsAssertDebug(phoneNumberWithAreaCodeIfMissing.hasPrefix("+"))
            tryParsing(phoneNumberWithAreaCodeIfMissing)
        }

        return results
    }

    /// Adds the local user's area code to `normalizedText` if it doesn't have its own.
    private static func phoneNumberWithAreaCodeIfMissing(
        normalizedText: String,
        localCallingCode: Int,
        localPhoneNumber: String
    ) -> String? {
        switch localCallingCode {
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
        localCallingCode: Int,
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
        if let transformRule = nationalPrefixTransformRuleCache[countryCode] {
            return transformRule
        }
        let transformRule: String? = NBMetadataHelper().getMetadataForRegion(countryCode)?.nationalPrefixTransformRule
        nationalPrefixTransformRuleCache[countryCode] = transformRule
        return transformRule
    }
}
