//  Created by Frederic Jacobs on 28/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import <Foundation/Foundation.h>
@class TSNumberVerifier;

#ifndef TextSecureKit_Constants_h
#define TextSecureKit_Constants_h

typedef NS_ENUM(NSInteger, TSWhisperMessageType) {
    TSUnknownMessageType            = 0,
    TSEncryptedWhisperMessageType   = 1,
    TSIgnoreOnIOSWhisperMessageType = 2, // on droid this is the prekey bundle message irrelevant for us
    TSPreKeyWhisperMessageType      = 3,
    TSUnencryptedWhisperMessageType = 4,
};

typedef enum { kSMSVerification, kPhoneNumberVerification } VerificationTransportType;

#pragma mark Server Address

#define textSecureHTTPTimeOut 10

#define textSecureWebSocketAPI @"wss://textsecure-service.whispersystems.org/v1/websocket/"
#define textSecureServerURL @"https://textsecure-service.whispersystems.org/"

//#define textSecureWebSocketAPI    @"wss://textsecure-service-staging.whispersystems.org/v1/websocket/"
//#define textSecureServerURL       @"https://textsecure-service-staging.whispersystems.org/"

#define textSecureGeneralAPI @"v1"
#define textSecureAccountsAPI @"v1/accounts"
#define textSecureAttributesAPI @"/attributes/"

#define textSecureMessagesAPI @"v1/messages/"
#define textSecureKeysAPI @"v2/keys"
#define textSecureSignedKeysAPI @"v2/keys/signed"
#define textSecureDirectoryAPI @"v1/directory"
#define textSecureAttachmentsAPI @"v1/attachments"


typedef void (^successCompletionBlock)(void);
typedef void (^failedRegistrationRequestBlock)(void);


#pragma mark Push RegistrationSpecific Constants
typedef NS_ENUM(NSInteger, TSPushRegistrationError) {
    TSPushRegistrationErrorNetwork,
    TSPushRegistrationErrorAuthentication,
    TSPushRegistrationErrorRequest
};

typedef void (^failedPushRegistrationRequestBlock)(TSPushRegistrationError error);


#endif
