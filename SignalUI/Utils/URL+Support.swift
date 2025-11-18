//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension URL {
    public enum Support {
        public static let backups: URL = .supportArticle("9708267671322")
        public static let contactAccessNotAllowed: URL = .supportArticle("360007319011#ipad_contacts")
        public static let debugLogs: URL = .supportArticle("360007318591")
        public static let deliveryIssue: URL = .supportArticle("4404859745690")
        public static let generic: URL = URL(string: "https://support.signal.org")!
        public static let groups: URL = .supportArticle("360007319331")
        public static let inactivePrimaryDevice: URL = .supportArticle("9021007554074")
        public static let linkedDevices: URL = .supportArticle("360007320551")
        public static let pin: URL = .supportArticle("360007059792")
        public static let profilesAndMessageRequests: URL = .supportArticle("360007459591")
        public static let proxies: URL = .supportArticle("360056052052")
        public static let requestingAccountData: URL = .supportArticle("5538911756954")
        public static let safetyNumbers: URL = .supportArticle("360007060632")
        public static let troubleshootingMultipleDevices: URL = .supportArticle("360007320451")
        public static let unsupportedOS: URL = .supportArticle("5109141421850")

        public enum Donations {
            public static let badgeExpiration: URL = .supportArticle("360031949872#fix")
            public static let donationPending: URL = .supportArticle("360031949872#pending")
            public static let donorFAQ: URL = .supportArticle("360031949872")
            public static let subscriptionFAQ: URL = .supportArticle("4408365318426")
        }

        public enum Payments {
            public static let currencyConversion: URL = .supportArticle("360057625692#payments_currency_conversion")
            public static let deactivate: URL = .supportArticle("360057625692#payments_deactivate")
            public static let details: URL = .supportArticle("360057625692#payments_details")
            public static let transferFromExchange: URL = .supportArticle("360057625692#payments_transfer_from_exchange")
            public static let transferToExchange: URL = .supportArticle("360057625692#payments_transfer_to_exchange")
            public static let walletRestorePassphrase: URL = .supportArticle("360057625692#payments_wallet_restore_passphrase")
            public static let walletViewPassphrase: URL = .supportArticle("360057625692#payments_wallet_view_passphrase")
            public static let whichOnes: URL = .supportArticle("360057625692#payments_which_ones")
        }
    }

    private static func supportArticle(_ slug: String) -> URL {
        self.init(string: "https://support.signal.org/hc/articles/\(slug)")!
    }
}
