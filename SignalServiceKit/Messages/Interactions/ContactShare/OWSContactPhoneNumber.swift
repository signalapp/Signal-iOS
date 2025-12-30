//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Contacts

@objc(OWSContactPhoneNumber)
public final class OWSContactPhoneNumber: NSObject, NSCoding, NSCopying, OWSContactField {
    public init?(coder: NSCoder) {
        self.label = coder.decodeObject(of: NSString.self, forKey: "label") as String?
        self.phoneNumber = coder.decodeObject(of: NSString.self, forKey: "phoneNumber") as String? ?? ""
        self.type = (coder.decodeObject(of: NSNumber.self, forKey: "phoneType")?.intValue).flatMap(`Type`.init(rawValue:)) ?? .home
    }

    public func encode(with coder: NSCoder) {
        if let label {
            coder.encode(label, forKey: "label")
        }
        coder.encode(self.phoneNumber, forKey: "phoneNumber")
        coder.encode(NSNumber(value: self.type.rawValue), forKey: "phoneType")
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(label)
        hasher.combine(phoneNumber)
        hasher.combine(type)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard Swift.type(of: self) == Swift.type(of: object) else { return false }
        guard self.label == object.label else { return false }
        guard self.phoneNumber == object.phoneNumber else { return false }
        guard self.type == object.type else { return false }
        return true
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        return self
    }

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

    public let type: `Type`

    // Applies in the Type.custom case.
    public let label: String?
    public let phoneNumber: String

    public init(type: Type, label: String? = nil, phoneNumber: String) {
        self.type = type
        self.label = label
        self.phoneNumber = phoneNumber
        super.init()
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
                labeledValueType: CNLabeledValue<CNPhoneNumber>.self,
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
