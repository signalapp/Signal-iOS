//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Contacts

@objc(OWSContactPhoneNumber)
public class OWSContactPhoneNumber: MTLModel, OWSContactField {

    @objc(OWSContactPhoneType)
    public enum `Type`: Int, CustomStringConvertible {
        case home = 1
        case mobile
        case work
        case custom

        public var description: String {
            switch self {
            case .home: return "Home"
            case .mobile: return "Mobile"
            case .work: return "Work"
            case .custom: return "Custom"
            }
        }
    }

    @objc(phoneType)
    public private(set) var type: `Type` = .home

    // Applies in the Type.custom case.
    @objc
    public private(set) var label: String?

    @objc
    public private(set) var phoneNumber: String = ""

    public override init() {
        super.init()
    }

    public init(type: Type, label: String? = nil, phoneNumber: String) {
        self.type = type
        self.label = label
        self.phoneNumber = phoneNumber
        super.init()
    }

    required init!(coder: NSCoder!) {
        super.init(coder: coder)
    }

    required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    public var e164: String? {
        return SSKEnvironment.shared.phoneNumberUtilRef.parsePhoneNumber(userSpecifiedText: phoneNumber)?.e164
    }

    // MARK: OWSContactField

    public var isValid: Bool {
        guard !phoneNumber.stripped.isEmpty else {
            Logger.warn("invalid phone number: \(phoneNumber).")
            return false
        }
        return true
    }

    public var localizedLabel: String {
        switch type {
        case .home:
            return CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: CNLabelHome)

        case .mobile:
            return CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: CNLabelPhoneNumberMobile)

        case .work:
            return CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: CNLabelWork)

        case .custom:
            guard let label = label?.strippedOrNil else {
                return OWSLocalizedString("CONTACT_PHONE", comment: "Label for a contact's phone number.")
            }
            return label
        }
    }
}

// MARK: CNContact Conversion

extension OWSContactPhoneNumber {

    public convenience init(cnLabeledValue: CNLabeledValue<CNPhoneNumber>) {
        // Make a best effort to parse the phone number to e164.
        let unparsedPhoneNumber = cnLabeledValue.value.stringValue
        let parsedPhoneNumber = SSKEnvironment.shared.phoneNumberUtilRef.parsePhoneNumber(userSpecifiedText: unparsedPhoneNumber)?.e164 ?? unparsedPhoneNumber

        let customLabel: String?
        let type: `Type`
        switch cnLabeledValue.label {
        case CNLabelHome:
            type = .home
            customLabel = nil

        case CNLabelWork:
            type = .work
            customLabel = nil

        case CNLabelPhoneNumberMobile:
            type = .mobile
            customLabel = nil

        default:
            type = .custom
            customLabel = SystemContact.localizedString(
                forCNLabel: cnLabeledValue.label,
                labeledValueType: CNLabeledValue<CNPhoneNumber>.self
            )
        }

        self.init(type: type, label: customLabel, phoneNumber: parsedPhoneNumber)
    }

    public func cnLabeledValue() -> CNLabeledValue<CNPhoneNumber> {
        let cnPhoneNumber = CNPhoneNumber(stringValue: phoneNumber)
        let cnLabel: String? = {
            switch type {
            case .home:
                return CNLabelHome
            case .mobile:
                return CNLabelPhoneNumberMobile
            case .work:
                return CNLabelWork
            case .custom:
                return label
            }
        }()
        return CNLabeledValue(label: cnLabel, value: cnPhoneNumber)
    }
}

// MARK: - Protobuf

extension OWSContactPhoneNumber {

    public convenience init?(proto: SSKProtoDataMessageContactPhone) {
        guard proto.hasValue, let phoneNumber = proto.value?.strippedOrNil else { return nil }

        let type: `Type`
        if proto.hasType {
            switch proto.unwrappedType {
            case .home:
                type = .home

            case .mobile:
                type = .mobile

            case .work:
                type = .work

            default:
                type = .custom
            }
        } else {
            type = .custom
        }

        let label: String?
        if proto.hasLabel {
            label = proto.label?.strippedOrNil
        } else {
            label = nil
        }

        self.init(type: type, label: label, phoneNumber: phoneNumber)
    }

    public func proto() -> SSKProtoDataMessageContactPhone? {
        guard isValid else { return nil }

        let builder = SSKProtoDataMessageContactPhone.builder()
        builder.setValue(phoneNumber)
        if let label = label?.strippedOrNil {
            builder.setLabel(label)
        }
        let type: SSKProtoDataMessageContactPhoneType = {
            switch self.type {
            case .home: return .home
            case .work: return .work
            case .mobile: return .mobile
            case .custom: return .custom
            }
        }()
        builder.setType(type)

        return builder.buildInfallibly()
    }
}
