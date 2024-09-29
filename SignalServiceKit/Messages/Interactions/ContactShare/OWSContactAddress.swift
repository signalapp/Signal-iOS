//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Contacts

@objc(OWSContactAddress)
public class OWSContactAddress: MTLModel, OWSContactField {

    @objc(OWSContactAddressType)
    public enum `Type`: Int, CustomStringConvertible {
        case home = 1
        case work
        case custom

        public var description: String {
            switch self {
            case .home: return "Home"
            case .work: return "Work"
            case .custom: return "Custom"
            }
        }
    }

    @objc(addressType)
    public private(set) var type: `Type` = .home

    // Applies in the Type.custom case.
    @objc
    public private(set) var label: String?

    @objc
    public fileprivate(set) var street: String?
    @objc
    public fileprivate(set) var pobox: String?
    @objc
    public fileprivate(set) var neighborhood: String?
    @objc
    public fileprivate(set) var city: String?
    @objc
    public fileprivate(set) var region: String?
    @objc
    public fileprivate(set) var postcode: String?
    @objc
    public fileprivate(set) var country: String?

    public override init() {
        super.init()
    }

    public init(
        type: `Type`,
        label: String? = nil,
        street: String? = nil,
        pobox: String? = nil,
        neighborhood: String? = nil,
        city: String? = nil,
        region: String? = nil,
        postcode: String? = nil,
        country: String? = nil
    ) {
        self.type = type
        self.label = label
        self.street = street
        self.pobox = pobox
        self.neighborhood = neighborhood
        self.city = city
        self.region = region
        self.postcode = postcode
        self.country = country
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
        let fields: [String?] = [ street, pobox, neighborhood, city, region, postcode, country ]
        for field in fields {
            if field?.strippedOrNil != nil {
                return true
            }
        }
        Logger.warn("Invalid address: empty")
        return false
    }

    public var localizedLabel: String {
        switch type {
        case .home:
            return CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: CNLabelHome)

        case .work:
            return CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: CNLabelWork)

        case .custom:
            guard let label = label?.strippedOrNil else {
                return OWSLocalizedString("CONTACT_ADDRESS", comment: "Label for a contact's postal address.")
            }
            return label
        }
    }
}

// MARK: CNContact Conversion

extension OWSContactAddress {

    public convenience init(cnLabeledValue: CNLabeledValue<CNPostalAddress>) {
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
                labeledValueType: CNLabeledValue<CNPostalAddress>.self
            )
        }
        let cnPostalAddress = cnLabeledValue.value
        self.init(
            type: type,
            label: customLabel,
            street: cnPostalAddress.street,
            pobox: nil,
            neighborhood: nil,
            city: cnPostalAddress.city,
            region: cnPostalAddress.state,
            postcode: cnPostalAddress.postalCode,
            country: cnPostalAddress.isoCountryCode
        )
    }

    public func cnLabeledValue() -> CNLabeledValue<CNPostalAddress>? {
        guard isValid else { return nil }

        let cnPostalAddress = CNMutablePostalAddress()
        cnPostalAddress.street = street ?? ""
        // TODO: Is this the correct mapping?
        // cnPostalAddress.subLocality = address.neighborhood;
        cnPostalAddress.city = city ?? ""
        // TODO: Is this the correct mapping?
        // cnPostalAddress.subAdministrativeArea = address.region;
        cnPostalAddress.state = region ?? ""
        cnPostalAddress.postalCode = postcode ?? ""
        // TODO: Should we be using 2-letter codes, 3-letter codes or names?
        if let country {
            cnPostalAddress.isoCountryCode = country
            cnPostalAddress.country = PhoneNumberUtil.countryName(fromCountryCode: country)
        }

        let cnLabel: String? = {
            switch type {
            case .home:
                return CNLabelHome
            case .work:
                return CNLabelWork
            case .custom:
                return label
            }
        }()
        return CNLabeledValue(label: cnLabel, value: cnPostalAddress)
    }
}

// MARK: - Protobuf

extension OWSContactAddress {

    public convenience init?(proto: SSKProtoDataMessageContactPostalAddress) {
        let type: `Type`
        if proto.hasType {
             switch proto.unwrappedType {
             case .home:
                 type = .home

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

        self.init(type: type, label: label)

         if proto.hasStreet {
             street = proto.street?.strippedOrNil
         }
         if proto.hasPobox {
             pobox = proto.pobox?.strippedOrNil
         }
         if proto.hasNeighborhood {
             neighborhood = proto.neighborhood?.strippedOrNil
         }
         if proto.hasCity {
             city = proto.city?.strippedOrNil
         }
         if proto.hasRegion {
             region = proto.region?.strippedOrNil
         }
         if proto.hasPostcode {
             postcode = proto.postcode?.strippedOrNil
         }
         if proto.hasCountry {
             country = proto.country?.strippedOrNil
         }

        guard isValid else { return nil }
    }

    public func proto() -> SSKProtoDataMessageContactPostalAddress? {
        guard isValid else { return nil }

        let builder = SSKProtoDataMessageContactPostalAddress.builder()

        if let label = label?.strippedOrNil {
            builder.setLabel(label)
        }

        let type: SSKProtoDataMessageContactPostalAddressType = {
            switch self.type {
            case .home: return .home
            case .work: return .work
            case .custom: return .custom
            }
        }()
        builder.setType(type)

        if let value = street?.strippedOrNil {
            builder.setStreet(value)
        }
        if let value = pobox?.strippedOrNil {
            builder.setPobox(value)
        }
        if let value = neighborhood?.strippedOrNil {
            builder.setNeighborhood(value)
        }
        if let value = city?.strippedOrNil {
            builder.setCity(value)
        }
        if let value = region?.strippedOrNil {
            builder.setRegion(value)
        }
        if let value = postcode?.strippedOrNil {
            builder.setPostcode(value)
        }
        if let value = country?.strippedOrNil {
            builder.setCountry(value)
        }

        return builder.buildInfallibly()
    }
}
