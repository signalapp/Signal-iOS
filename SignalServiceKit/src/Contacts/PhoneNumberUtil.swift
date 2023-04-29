//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import libPhoneNumber_iOS

@objc
public class PhoneNumberUtilWrapper: NSObject {

    fileprivate let nbPhoneNumberUtil = NBPhoneNumberUtil()
    fileprivate var countryCodesFromCallingCodeCache = [String: [String]]()
    fileprivate let parsedPhoneNumberCache = LRUCache<String, NBPhoneNumber>(maxSize: 256, nseMaxSize: 0, shouldEvacuateInBackground: false)
}

// MARK: -

fileprivate extension PhoneNumberUtilWrapper {

    // country code -> calling code
    func callingCode(fromCountryCode countryCode: String) -> String? {
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

        let countryCallingCode = getCountryCode(forRegion: countryCode)
        let callingCode = COUNTRY_CODE_PREFIX + "\(countryCallingCode.intValue)"
        return callingCode
    }

    // Returns a list of country codes for a calling code in descending
    // order of population.
    func countryCodes(fromCallingCode callingCode: String) -> [String] {
        guard let callingCode = callingCode.nilIfEmpty else {
            return []
        }
        if let cachedValue = countryCodesFromCallingCodeCache[callingCode] {
            return cachedValue
        }
        let countryCodes: [String] = Self.countryCodesSortedByPopulationDescending.compactMap { (countryCode: String) -> String? in
            let callingCodeForCountryCode: String? = self.callingCode(fromCountryCode: countryCode)
            guard callingCode == callingCodeForCountryCode else {
                return nil
            }
            return countryCode
        }
        countryCodesFromCallingCodeCache[callingCode] = countryCodes
        return countryCodes
    }

    func format(phoneNumber: NBPhoneNumber, numberFormat: NBEPhoneNumberFormat) throws -> String {
        try nbPhoneNumberUtil.format(phoneNumber, numberFormat: numberFormat)
    }

    func parse(_ numberToParse: String, defaultRegion: String) throws -> NBPhoneNumber {
        let hashKey = "numberToParse:\(numberToParse), defaultRegion:\(defaultRegion)"
        if let cachedValue = parsedPhoneNumberCache[hashKey] {
            return cachedValue
        }
        let result = try nbPhoneNumberUtil.parse(numberToParse, defaultRegion: defaultRegion)
        parsedPhoneNumberCache[hashKey] = result
        return result
    }

    func examplePhoneNumber(forCountryCode countryCode: String) -> String? {
        // Signal users are very likely using mobile devices, so prefer that kind of example.
        do {
            func findExamplePhoneNumber() -> NBPhoneNumber? {
                if let nbPhoneNumber = PhoneNumberUtil.getExampleNumber(forType: countryCode,
                                                                        type: .MOBILE,
                                                                        nbPhoneNumberUtil: nbPhoneNumberUtil) {
                    return nbPhoneNumber
                }
                if let nbPhoneNumber = PhoneNumberUtil.getExampleNumber(forType: countryCode,
                                                                        type: .FIXED_LINE_OR_MOBILE,
                                                                        nbPhoneNumberUtil: nbPhoneNumberUtil) {
                    return nbPhoneNumber
                }
                return nil
            }
            guard let nbPhoneNumber = findExamplePhoneNumber() else {
                if CurrentAppContext().isRunningTests {
                    Logger.warn("Could not find example phone number for: \(countryCode)")
                } else {
                    owsFailDebug("Could not find example phone number for: \(countryCode)")
                }
                return nil
            }
            return try nbPhoneNumberUtil.format(nbPhoneNumber, numberFormat: .E164)
        } catch {
            if CurrentAppContext().isRunningTests {
                Logger.warn("Error: \(error)")
            } else {
                owsFailDebug("Error: \(error)")
            }
            return nil
        }
    }

    func isPossibleNumber(_ number: NBPhoneNumber) -> Bool {
        nbPhoneNumberUtil.isPossibleNumber(number)
    }

    func countryCodeByCarrier() -> String {
        nbPhoneNumberUtil.countryCodeByCarrier()
    }

    func getRegionCodeForCountryCode(_ countryCallingCode: NSNumber) -> String? {
        nbPhoneNumberUtil.getRegionCode(forCountryCode: countryCallingCode)
    }

    func isValidNumber(_ number: NBPhoneNumber) -> Bool {
        nbPhoneNumberUtil.isValidNumber(number)
    }

    func getCountryCode(forRegion regionCode: String) -> NSNumber {
        nbPhoneNumberUtil.getCountryCode(forRegion: regionCode)
    }

    func getNationalSignificantNumber(_ number: NBPhoneNumber) -> String {
        return nbPhoneNumberUtil.getNationalSignificantNumber(number)
    }
}

// MARK: -

@objc
extension PhoneNumberUtil {
    private static let unfairLock = UnfairLock()
    private var unfairLock: UnfairLock { Self.unfairLock }

    @objc(nationalNumberFromPhoneNumber:)
    public func nationalNumber(phoneNumber: NBPhoneNumber) -> String {
        return phoneNumberUtilWrapper.getNationalSignificantNumber(phoneNumber)
    }

    @objc(callingCodeFromCountryCode:)
    public static func callingCode(fromCountryCode countryCode: String) -> String? {
        shared.callingCode(fromCountryCode: countryCode)
    }

    @objc(callingCodeFromCountryCode:)
    public func callingCode(fromCountryCode countryCode: String) -> String? {
        unfairLock.withLock {
            phoneNumberUtilWrapper.callingCode(fromCountryCode: countryCode)
        }
    }

    @objc(countryCodesFromCallingCode:)
    public static func countryCodes(fromCallingCode callingCode: String) -> [String] {
        shared.countryCodes(fromCallingCode: callingCode)
    }

    // Returns a list of country codes for a calling code in descending
    // order of population.
    @objc(countryCodesFromCallingCode:)
    public func countryCodes(fromCallingCode callingCode: String) -> [String] {
        unfairLock.withLock {
            phoneNumberUtilWrapper.countryCodes(fromCallingCode: callingCode)
        }
    }

    /// Returns the most likely country code for a calling code based on population.
    /// If no country codes are found, returns the empty string.
    @objc(probableCountryCodeForCallingCode:)
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
    @objc(countryCodesForSearchTerm:)
    public class func countryCodes(forSearchTerm searchTerm: String?) -> [String] {
        let cleanedSearch = (searchTerm ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let codes = NSLocale.isoCountryCodes.filter { countryCode in
            guard
                let callingCode = callingCode(fromCountryCode: countryCode),
                !callingCode.isEmpty,
                callingCode != "+0"
            else {
                return false
            }
            let countryName = countryName(fromCountryCode: countryCode)
            return (
                cleanedSearch.isEmpty ||
                does(countryName, matchQuery: cleanedSearch) ||
                does(countryCode, matchQuery: cleanedSearch) ||
                callingCode.contains(cleanedSearch)
            )
        }

        return codes.sorted { lhs, rhs in
            let lhsCountry = countryName(fromCountryCode: lhs)
            let rhsCountry = countryName(fromCountryCode: rhs)
            return lhsCountry.localizedCaseInsensitiveCompare(rhsCountry) == .orderedAscending
        }
    }

    /// Convert country code to country name.
    @objc(countryNameFromCountryCode:)
    public class func countryName(fromCountryCode countryCode: String) -> String {
        lazy var unknownValue =  NSLocalizedString(
            "UNKNOWN_VALUE",
            comment: "Indicates an unknown or unrecognizable value."
        )

        if countryCode.isEmpty {
            return unknownValue
        }

        let identifier = NSLocale.localeIdentifier(fromComponents: [
            NSLocale.Key.countryCode.rawValue: countryCode
        ])

        let localesToTry = [Locale.current, NSLocale.system]
        for locale in localesToTry {
            let nsLocale = locale as NSLocale
            if let result = nsLocale.displayName(forKey: .identifier, value: identifier)?.nilIfEmpty {
                return result
            }
        }

        return unknownValue
    }

    public func format(_ phoneNumber: NBPhoneNumber, numberFormat: NBEPhoneNumberFormat) throws -> String {
        try unfairLock.withLock {
            try phoneNumberUtilWrapper.format(phoneNumber: phoneNumber, numberFormat: numberFormat)
        }
    }

    public func parse(_ numberToParse: String, defaultRegion: String) throws -> NBPhoneNumber {
        try unfairLock.withLock {
            try phoneNumberUtilWrapper.parse(numberToParse, defaultRegion: defaultRegion)
        }
    }

    public func examplePhoneNumber(forCountryCode countryCode: String) -> String? {
        unfairLock.withLock {
            phoneNumberUtilWrapper.examplePhoneNumber(forCountryCode: countryCode)
        }
    }

    public func isPossibleNumber(_ number: NBPhoneNumber) -> Bool {
        unfairLock.withLock {
            phoneNumberUtilWrapper.isPossibleNumber(number)
        }
    }

    public func countryCodeByCarrier() -> String {
        unfairLock.withLock {
            phoneNumberUtilWrapper.countryCodeByCarrier()
        }
    }

    public func getRegionCodeForCountryCode(_ countryCallingCode: NSNumber) -> String? {
        unfairLock.withLock {
            phoneNumberUtilWrapper.getRegionCodeForCountryCode(countryCallingCode)
        }
    }

    public func isValidNumber(_ number: NBPhoneNumber) -> Bool {
        unfairLock.withLock {
            phoneNumberUtilWrapper.isValidNumber(number)
        }
    }

    public func getCountryCode(forRegion regionCode: String) -> NSNumber {
        unfairLock.withLock {
            phoneNumberUtilWrapper.getCountryCode(forRegion: regionCode)
        }
    }
}

// MARK: -

fileprivate extension PhoneNumberUtilWrapper {
    static let countryCodesSortedByPopulationDescending: [String] = [
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
        "UM" // 0
        ]
}
