//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Contacts

@objc(OWSContactEmail)
public class OWSContactEmail: MTLModel, OWSContactField {

    @objc(OWSContactEmailType)
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

    @objc(emailType)
    public private(set) var type: `Type` = .home

    // Applies in the Type.custom case.
    @objc
    public private(set) var label: String?

    @objc
    public private(set) var email: String = ""

    public override init() {
        super.init()
    }

    public init(type: Type, label: String? = nil, email: String) {
        self.type = type
        self.label = label
        self.email = email
        super.init()
    }

    required init!(coder: NSCoder!) {
        super.init(coder: coder)
    }

    required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    // MARK: OWSContactField

    public var isValid: Bool {
        guard !email.stripped.isEmpty else {
            Logger.warn("invalid email: \(email).")
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
                return OWSLocalizedString("CONTACT_EMAIL", comment: "Label for a contact's email address.")
            }
            return label
        }
    }
}

// MARK: CNContact Conversion

extension OWSContactEmail {

    public convenience init(cnLabeledValue: CNLabeledValue<NSString>) {
        let email = cnLabeledValue.value as String

        let customLabel: String?
        let type: `Type`
        switch cnLabeledValue.label {
        case CNLabelHome:
            type = .home
            customLabel = nil

        case CNLabelWork:
            type = .work
            customLabel = nil

        default:
            type = .custom
            customLabel = SystemContact.localizedString(
                forCNLabel: cnLabeledValue.label,
                labeledValueType: CNLabeledValue<NSString>.self
            )
        }

        self.init(type: type, label: customLabel, email: email)
    }

    public func cnLabeledValue() -> CNLabeledValue<NSString> {
        let cnLabel: String? = {
            switch type {
            case .home:
                return CNLabelHome
            case .mobile:
                return "Mobile"
            case .work:
                return CNLabelWork
            case .custom:
                return label
            }
        }()
        return CNLabeledValue(label: cnLabel, value: email as NSString)
    }
}

// MARK: - Protobuf

extension OWSContactEmail {

    public convenience init?(proto: SSKProtoDataMessageContactEmail) {
        guard proto.hasValue, let email = proto.value?.strippedOrNil else { return nil }

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

        self.init(type: type, label: label, email: email)
    }

    public func proto() -> SSKProtoDataMessageContactEmail? {
        guard isValid else { return nil }

        let builder = SSKProtoDataMessageContactEmail.builder()
        builder.setValue(email)
        if let label = label?.strippedOrNil {
            builder.setLabel(label)
        }
        let type: SSKProtoDataMessageContactEmailType = {
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
