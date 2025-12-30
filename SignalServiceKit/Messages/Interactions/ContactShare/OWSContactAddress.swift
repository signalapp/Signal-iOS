//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Contacts

@objc(OWSContactAddress)
public final class OWSContactAddress: NSObject, NSCoding, NSCopying, OWSContactField {
    public init?(coder: NSCoder) {
        self.type = (coder.decodeObject(of: NSNumber.self, forKey: "addressType")?.intValue).flatMap(`Type`.init(rawValue:)) ?? .home
        self.city = coder.decodeObject(of: NSString.self, forKey: "city") as String?
        self.country = coder.decodeObject(of: NSString.self, forKey: "country") as String?
        self.label = coder.decodeObject(of: NSString.self, forKey: "label") as String?
        self.neighborhood = coder.decodeObject(of: NSString.self, forKey: "neighborhood") as String?
        self.pobox = coder.decodeObject(of: NSString.self, forKey: "pobox") as String?
        self.postcode = coder.decodeObject(of: NSString.self, forKey: "postcode") as String?
        self.region = coder.decodeObject(of: NSString.self, forKey: "region") as String?
        self.street = coder.decodeObject(of: NSString.self, forKey: "street") as String?
    }

    public func encode(with coder: NSCoder) {
        coder.encode(NSNumber(value: self.type.rawValue), forKey: "addressType")
        if let city {
            coder.encode(city, forKey: "city")
        }
        if let country {
            coder.encode(country, forKey: "country")
        }
        if let label {
            coder.encode(label, forKey: "label")
        }
        if let neighborhood {
            coder.encode(neighborhood, forKey: "neighborhood")
        }
        if let pobox {
            coder.encode(pobox, forKey: "pobox")
        }
        if let postcode {
            coder.encode(postcode, forKey: "postcode")
        }
        if let region {
            coder.encode(region, forKey: "region")
        }
        if let street {
            coder.encode(street, forKey: "street")
        }
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(type)
        hasher.combine(city)
        hasher.combine(country)
        hasher.combine(label)
        hasher.combine(neighborhood)
        hasher.combine(pobox)
        hasher.combine(postcode)
        hasher.combine(region)
        hasher.combine(street)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard Swift.type(of: self) == Swift.type(of: object) else { return false }
        guard self.type == object.type else { return false }
        guard self.city == object.city else { return false }
        guard self.country == object.country else { return false }
        guard self.label == object.label else { return false }
        guard self.neighborhood == object.neighborhood else { return false }
        guard self.pobox == object.pobox else { return false }
        guard self.postcode == object.postcode else { return false }
        guard self.region == object.region else { return false }
        guard self.street == object.street else { return false }
        return true
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        return self
    }

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

    public let type: `Type`

    // Applies in the Type.custom case.
    public let label: String?
    public let street: String?
    public let pobox: String?
    public let neighborhood: String?
    public let city: String?
    public let region: String?
    public let postcode: String?
    public let country: String?

    public init(
        type: `Type`,
        label: String? = nil,
        street: String? = nil,
        pobox: String? = nil,
        neighborhood: String? = nil,
        city: String? = nil,
        region: String? = nil,
        postcode: String? = nil,
        country: String? = nil,
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

    // MARK: OWSContactField

    public var isValid: Bool {
        let fields: [String?] = [street, pobox, neighborhood, city, region, postcode, country]
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
                labeledValueType: CNLabeledValue<CNPostalAddress>.self,
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
            country: cnPostalAddress.isoCountryCode,
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

        self.init(
            type: type,
            label: label,
            street: proto.hasStreet ? proto.street?.strippedOrNil : nil,
            pobox: proto.hasPobox ? proto.pobox?.strippedOrNil : nil,
            neighborhood: proto.hasNeighborhood ? proto.neighborhood?.strippedOrNil : nil,
            city: proto.hasCity ? proto.city?.strippedOrNil : nil,
            region: proto.hasRegion ? proto.region?.strippedOrNil : nil,
            postcode: proto.hasPostcode ? proto.postcode?.strippedOrNil : nil,
            country: proto.hasCountry ? proto.country?.strippedOrNil : nil,
        )

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
