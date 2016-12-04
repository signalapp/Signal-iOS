//  Created by Michael Kirk on 12/3/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

import Foundation

@objc(OWSContactPresenter)
protocol ContactAdaptee {
    init(contact aContact: Contact)

    var fullName: String { get }
    func formattedFullName(font: UIFont) -> NSAttributedString?
}

@objc(OWSContactAdapter)
class ContactAdapter: NSObject {

    let adaptee: ContactAdaptee
    let contact: Contact

    required init(contact aContact: Contact) {
        contact = aContact
        if #available(iOS 9, *) {
            adaptee = ContactAdapteeIOS9(contact: aContact)
        } else {
            adaptee = ContactAdapteeIOS8(contact: aContact)
        }
    }

    var image: UIImage? {
        get { return contact.image }
    }

    var uniqueId: String {
        get { return contact.uniqueId }
    }


    var hasName: Bool {
        get { return fullName.isEmpty }
    }

    /**
     * Possible empty string.
     */
    var fullName: String {
        get { return adaptee.fullName }
    }

    var signalIdentifiers: [String] {
        get { return contact.textSecureIdentifiers() }
    }

    var displayName: String {
        get {
            if hasName {
                return fullName
            } else if signalIdentifiers.count > 0 {
                return signalIdentifiers.first!
            } else {
                return NSLocalizedString("UNKNOWN_CONTACT_NAME",
                                         comment: "Displayed if for some reason we can't determine a contacts phone number *or* name");
            }
        }
    }

    func formattedFullName(font: UIFont) -> NSAttributedString? {
        return adaptee.formattedFullName(font: font)
    }

    var initials: String {
        get {
            if hasName {
                return buildInitials(name: fullName)
            } else {
                return "#"
            }
        }
    }

    // FIXME TODO
    fileprivate func buildInitials(name: String) -> String {
        let words = name.components(separatedBy: CharacterSet.whitespacesAndNewlines)

        let letters = words.map { word in
            return word[0]
        }.joined()

        return letters[0..<3]
    }
}

// iOS 8.
class ContactAdapteeIOS8: ContactAdaptee {
    let contact: Contact
    let fullName: String

    required init(contact aContact: Contact) {
        contact = aContact
        // TODO extract from SSK Contact
        fullName = contact.fullName
    }

    func formattedFullName(font: UIFont) -> NSAttributedString? {
        let normalAttributes = [
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: UIColor.ows_darkGray()
        ]
        let boldDescriptor = font.fontDescriptor.withSymbolicTraits(.traitBold)
        let boldAttributes = [
            NSFontAttributeName: UIFont(descriptor:boldDescriptor!, size: 0),
            NSForegroundColorAttributeName: UIColor.ows_black()
        ]

        let sortByFirstName = ABPersonGetSortOrdering() == ABPersonSortOrdering(kABPersonSortByFirstName)

        var firstName: NSAttributedString? = nil
        if contact.firstName != nil {
            if sortByFirstName {
                firstName = NSAttributedString(string: contact.firstName!, attributes: boldAttributes)
            } else {
                firstName = NSAttributedString(string: contact.firstName!, attributes: normalAttributes)
            }
        }

        var lastName: NSAttributedString? = nil
        if contact.lastName != nil {
            if sortByFirstName {
                lastName = NSAttributedString(string: contact.lastName!, attributes: normalAttributes)
            } else {
                lastName = NSAttributedString(string: contact.lastName!, attributes: boldAttributes)
            }
        }

        let displayFirstNameFirst = ABPersonGetCompositeNameFormat() == ABPersonCompositeNameFormat(kABPersonCompositeNameFormatFirstNameFirst)

        let leftName: NSAttributedString?
        let rightName: NSAttributedString?
        if displayFirstNameFirst {
            leftName = firstName
            rightName = lastName
        } else {
            leftName = lastName
            rightName = firstName
        }

        if leftName != nil && rightName != nil {
            let formattedNameString = NSMutableAttributedString(attributedString: leftName!)
            formattedNameString.append(NSAttributedString(string:" "))
            formattedNameString.append(rightName!)
            return formattedNameString
        } else if leftName != nil {
            return leftName
        } else if rightName != nil {
            return rightName
        } else {
            return nil
        }
    }
}

// iOS 9+
@available(iOS 9.0, *)
class ContactAdapteeIOS9: ContactAdaptee {

    let contact: Contact
    let cnContact: CNContact
    let fullName: String

    required init(contact aContact: Contact) {
        contact = aContact
        cnContact = aContact.cnContact!
        // TODO build with contacts framework
        fullName = contact.fullName
    }

    /**
     * Bold the sorting portion of the name. e.g. if we sort by family name, bold the family name.
     */
    func formattedFullName(font: UIFont) -> NSAttributedString? {
        let keyToHighlight = ContactSortOrder == .familyName ? CNContactFamilyNameKey : CNContactGivenNameKey

        if let attributedName = CNContactFormatter.attributedString(from: cnContact, style: .fullName, defaultAttributes: nil) {
            let highlightedName = attributedName.mutableCopy() as! NSMutableAttributedString
            highlightedName.enumerateAttributes(in: NSMakeRange(0, highlightedName.length), options: [], using: { (attrs, range, stop) in
                if let property = attrs[CNContactPropertyAttribute] as? String, property == keyToHighlight {
                    let boldDescriptor = font.fontDescriptor.withSymbolicTraits(.traitBold)
                    let boldAttributes = [
                        NSFontAttributeName: UIFont(descriptor:boldDescriptor!, size: 0)
                    ]

                    highlightedName.addAttributes(boldAttributes, range: range)
                }
            })
            return highlightedName
        }
        return nil
    }

}

// TODO move this to separate file
fileprivate extension String {

    var length: Int {
        return self.characters.count
    }

    subscript (i: Int) -> String {
        return self[Range(i ..< i + 1)]
    }

    func substring(from: Int) -> String {
        return self[Range(min(from, length) ..< length)]
    }

    func substring(to: Int) -> String {
        return self[Range(0 ..< max(0, to))]
    }

    subscript (r: Range<Int>) -> String {
        let range = Range(uncheckedBounds: (lower: max(0, min(length, r.lowerBound)),
                                            upper: min(length, max(0, r.upperBound))))
        let start = index(startIndex, offsetBy: range.lowerBound)
        let end = index(start, offsetBy: range.upperBound - range.lowerBound)
        return self[Range(start ..< end)]
    }
    
}
