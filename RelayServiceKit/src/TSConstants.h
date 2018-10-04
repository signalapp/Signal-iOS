//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#ifndef TextSecureKit_Constants_h
#define TextSecureKit_Constants_h

typedef NS_ENUM(NSInteger, TSWhisperMessageType) {
    TSUnknownMessageType            = 0,
    TSEncryptedWhisperMessageType   = 1,
    TSIgnoreOnIOSWhisperMessageType = 2, // on droid this is the prekey bundle message irrelevant for us
    TSPreKeyWhisperMessageType      = 3,
    TSUnencryptedWhisperMessageType = 4,
};

#pragma mark Server Address

#define textSecureHTTPTimeOut 10

//#define CONVERSATION_COLORS_ENABLED

#define kSupportUrlString @"https://support.forsta.io/"

#define kLegalTermsUrlString @"https://forsta.io/terms/"
#define SHOW_LEGAL_TERMS_LINK

#ifdef DEBUG
#define CONTACT_DISCOVERY_SERVICE
#endif

// Notification strings
#define FLSettingsUpdatedNotification @"FLSettingsUpdatedNotification"
#define FLUserSelectedFromPopoverDirectoryNotification @"FLUserSelectedFromPopoverDirectoryNotification"
#define FLMarkAllReadNotification @"FLMarkAllReadNotification"
#define FLRecipientsNeedRefreshNotification @"FLRecipientsNeedRefreshNotification"
#define FLCCSMUsersUpdated @"FLCCSMUsersUpdated"
#define FLCCSMTagsUpdated @"FLCCSMTagsUpdated"
#define FLRegistrationStatusUpdateNotification @"FLRegistrationStatusUpdateNotification"

// Superman IDs - used for provisioning.
#define FLSupermanDevID @"1e1116aa-31b3-4fb2-a4db-21e8136d4f3a"
#define FLSupermanStageID @"88e7165e-d2da-4c3f-a14a-bb802bb0cefb"
#define FLSupermanProdID @"cf40fca2-dfa8-4356-8ae7-45f56f7551ca"

#define FLSupermanIds @[ FLSupermanDevID, FLSupermanStageID, FLSupermanProdID ]

//// Forsta CCSM home URLs
//#define FLForstaDevURL @"https://ccsm-dev-api.forsta.io"
//#define FLForstaStageURL @"https://ccsm-stage-api.forsta.io"
//#define FLForstaProdURL @"https://api.forsta.io"

//// Domain creation URLs
//#define FLDomainCreateDevURL @"https://ccsm-dev.forsta.io/create"
//#define FLDomainCreateStageURL @"https://ccsm-stage.forsta.io/create"
//#define FLDomainCreateProdURL @"https://console.forsta.io/create"

//// Forsta support URL
//#define FLForstaSupportURL @"https://support.forsta.io"

//// Forsta SMS invitation URL
//#define FLSMSInvitationURL @"https://www.forsta.io"

// TODO:  Flesh this for dev environment
//#if DEVELOPMENT
//    #define FLHomeURL FLForstaDevURL
//    #define FLDomainCreateURL FLDomainCreateDevURL
//    #define FLSupermanID FLSupermanDevID
//#else
//    #define FLHomeURL FLForstaProdURL
//    #define FLDomainCreateURL FLDomainCreateProdURL
//    #define FLSupermanID FLSupermanProdID
//#endif


//#ifndef DEBUG

// Production
//#define textSecureCDNServerURL @"https://cdn.signal.org"
// Use same reflector for service and CDN
//#define textSecureServiceReflectorHost @"textsecure-service-reflected.whispersystems.org"
//#define textSecureCDNReflectorHost @"textsecure-service-reflected.whispersystems.org"

//#else
//
//// Staging
//#define textSecureWebSocketAPI @"wss://textsecure-service-staging.whispersystems.org/v1/websocket/"
//#define textSecureServerURL @"https://textsecure-service-staging.whispersystems.org/"
//#define textSecureCDNServerURL @"https://cdn-staging.signal.org"
//#define textSecureServiceReflectorHost @"meek-signal-service-staging.appspot.com";
//#define textSecureCDNReflectorHost @"meek-signal-cdn-staging.appspot.com";
//
//#endif

#define textSecureAccountsAPI @"v1/accounts"
#define textSecureAttributesAPI @"/attributes/"

#define textSecureMessagesAPI @"v1/messages/"
#define textSecureKeysAPI @"v2/keys"
#define textSecureSignedKeysAPI @"v2/keys/signed"
#define textSecureDirectoryAPI @"v1/directory"
#define textSecureAttachmentsAPI @"v1/attachments"
#define textSecureDeviceProvisioningCodeAPI @"v1/devices/provisioning/code"
#define textSecureDeviceProvisioningAPIFormat @"v1/provisioning/%@"
#define textSecureDevicesAPIFormat @"v1/devices/%@"
#define textSecureProfileAPIFormat @"v1/profile/%@"
#define textSecureSetProfileNameAPIFormat @"v1/profile/name/%@"
#define textSecureProfileAvatarFormAPI @"v1/profile/form/avatar"
#define textSecure2FAAPI @"/v1/accounts/pin"

#endif
