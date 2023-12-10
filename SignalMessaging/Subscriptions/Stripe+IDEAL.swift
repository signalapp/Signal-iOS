//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Stripe.PaymentMethod {

    public struct IDEAL: Equatable {
        public let name: String
        public let email: String
        public let iDEALBank: IDEALBank

        public init(name: String, email: String, iDEALBank: IDEALBank) {
            self.name = name
            self.email = email
            self.iDEALBank = iDEALBank
        }
    }

    public enum IDEALBank: String, CaseIterable {
        case ABN_AMRO = "abn_amro"
        case ASN_BANK = "asn_bank"
        case BUNQ = "bunq"
        case ING = "ing"
        case KNAB = "knab"
        case N26 = "n26"
        case RABOBANK = "rabobank"
        case REGIOBANK = "regiobank"
        case REVOLUT = "revolut"
        case SNS_BANK = "sns_bank"
        case TRIODOS_BANK = "triodos_bank"
        case VAN_LANSCHOT = "van_lanschot"
        case YOURSAFE = "yoursafe"

        public var displayName: String {
            switch self {
            case .ABN_AMRO: return "ABN Amro"
            case .ASN_BANK: return "ASN Bank"
            case .BUNQ: return "bunq"
            case .ING: return "ING"
            case .KNAB: return "Knab"
            case .N26: return "N26"
            case .RABOBANK: return "Rabobank"
            case .REGIOBANK: return "RegioBank"
            case .REVOLUT: return "Revolut"
            case .SNS_BANK: return "SNS Bank"
            case .TRIODOS_BANK: return "Triodos Bank"
            case .VAN_LANSCHOT: return "Van Lanschot Kempen"
            case .YOURSAFE: return "Yoursafe"
            }
        }

        public var image: UIImage? {
            switch self {
            case .ABN_AMRO: return UIImage(named: "ideal_abn_amro")
            case .ASN_BANK: return UIImage(named: "ideal_asn")
            case .BUNQ: return UIImage(named: "ideal_bunq")
            case .ING: return UIImage(named: "ideal_ing")
            case .KNAB: return UIImage(named: "ideal_knab")
            case .N26: return UIImage(named: "ideal_n26")
            case .RABOBANK: return UIImage(named: "ideal_rabobank")
            case .REGIOBANK: return UIImage(named: "ideal_regiobank")
            case .REVOLUT: return UIImage(named: "ideal_revolut")
            case .SNS_BANK: return UIImage(named: "ideal_sns")
            case .TRIODOS_BANK: return UIImage(named: "ideal_triodos_bank")
            case .VAN_LANSCHOT: return UIImage(named: "ideal_van_lanchot")
            case .YOURSAFE: return UIImage(named: "ideal_yoursafe")
            }
        }
    }
}
