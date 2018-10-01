//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSRequestFactory.h"
#import "OWS2FAManager.h"
#import "OWSDevice.h"
#import "TSAttributes.h"
#import "TSConstants.h"
#import "TSRequest.h"
#import <AxolotlKit/NSData+keyVersionByte.h>
#import <AxolotlKit/SignedPreKeyRecord.h>
#import <Curve25519Kit/Curve25519.h>
#import <SignalCoreKit/NSData+OWS.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSRequestFactory

+ (TSRequest *)enable2FARequestWithPin:(NSString *)pin
{
    OWSAssertDebug(pin.length > 0);

    return [TSRequest requestWithUrl:[NSURL URLWithString:textSecure2FAAPI]
                              method:@"PUT"
                          parameters:@{
                              @"pin" : pin,
                          }];
}

+ (TSRequest *)disable2FARequest
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:textSecure2FAAPI] method:@"DELETE" parameters:@{}];
}

+ (TSRequest *)acknowledgeMessageDeliveryRequestWithSource:(NSString *)source timestamp:(UInt64)timestamp
{
    OWSAssertDebug(source.length > 0);
    OWSAssertDebug(timestamp > 0);

    NSString *path = [NSString stringWithFormat:@"v1/messages/%@/%llu", source, timestamp];

    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"DELETE" parameters:@{}];
}

+ (TSRequest *)deleteDeviceRequestWithDevice:(OWSDevice *)device
{
    OWSAssertDebug(device);

    NSString *path = [NSString stringWithFormat:textSecureDevicesAPIFormat, @(device.deviceId)];

    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"DELETE" parameters:@{}];
}

+ (TSRequest *)deviceProvisioningCodeRequest
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:textSecureDeviceProvisioningCodeAPI]
                              method:@"GET"
                          parameters:@{}];
}

+ (TSRequest *)deviceProvisioningRequestWithMessageBody:(NSData *)messageBody ephemeralDeviceId:(NSString *)deviceId
{
    OWSAssertDebug(messageBody.length > 0);
    OWSAssertDebug(deviceId.length > 0);

    NSString *path = [NSString stringWithFormat:textSecureDeviceProvisioningAPIFormat, deviceId];
    return [TSRequest requestWithUrl:[NSURL URLWithString:path]
                              method:@"PUT"
                          parameters:@{
                              @"body" : [messageBody base64EncodedString],
                          }];
}

+ (TSRequest *)getDevicesRequest
{
    NSString *path = [NSString stringWithFormat:textSecureDevicesAPIFormat, @""];
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
}

+ (TSRequest *)getMessagesRequest
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:@"v1/messages"] method:@"GET" parameters:@{}];
}

+ (TSRequest *)getProfileRequestWithRecipientId:(NSString *)recipientId
{
    OWSAssertDebug(recipientId.length > 0);

    NSString *path = [NSString stringWithFormat:textSecureProfileAPIFormat, recipientId];
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
}

+ (TSRequest *)turnServerInfoRequest
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:@"v1/accounts/turn"] method:@"GET" parameters:@{}];
}

+ (TSRequest *)allocAttachmentRequest
{
    NSString *path = [NSString stringWithFormat:@"%@", textSecureAttachmentsAPI];
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
}

+ (TSRequest *)attachmentRequestWithAttachmentId:(UInt64)attachmentId
{
    OWSAssertDebug(attachmentId > 0);

    NSString *path = [NSString stringWithFormat:@"%@/%llu", textSecureAttachmentsAPI, attachmentId];

    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
}

+ (TSRequest *)availablePreKeysCountRequest
{
    NSString *path = [NSString stringWithFormat:@"%@", textSecureKeysAPI];
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
}

+ (TSRequest *)contactsIntersectionRequestWithHashesArray:(NSArray<NSString *> *)hashes
{
    OWSAssertDebug(hashes.count > 0);

    NSString *path = [NSString stringWithFormat:@"%@/%@", textSecureDirectoryAPI, @"tokens"];
    return [TSRequest requestWithUrl:[NSURL URLWithString:path]
                              method:@"PUT"
                          parameters:@{
                              @"contacts" : hashes,
                          }];
}

+ (TSRequest *)currentSignedPreKeyRequest
{
    NSString *path = textSecureSignedKeysAPI;
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
}

+ (TSRequest *)profileAvatarUploadFormRequest
{
    NSString *path = textSecureProfileAvatarFormAPI;
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
}

+ (TSRequest *)recipientPrekeyRequestWithRecipient:(NSString *)recipientNumber deviceId:(NSString *)deviceId
{
    OWSAssertDebug(recipientNumber.length > 0);
    OWSAssertDebug(deviceId.length > 0);

    NSString *path = [NSString stringWithFormat:@"%@/%@/%@", textSecureKeysAPI, recipientNumber, deviceId];
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
}

+ (TSRequest *)registerForPushRequestWithPushIdentifier:(NSString *)identifier voipIdentifier:(NSString *)voipId
{
    OWSAssertDebug(identifier.length > 0);
    OWSAssertDebug(voipId.length > 0);

    NSString *path = [NSString stringWithFormat:@"%@/%@", textSecureAccountsAPI, @"apn"];
    OWSAssertDebug(voipId);
    return [TSRequest requestWithUrl:[NSURL URLWithString:path]
                              method:@"PUT"
                          parameters:@{
                              @"apnRegistrationId" : identifier,
                              @"voipRegistrationId" : voipId ?: @"",
                          }];
}

+ (TSRequest *)updateAttributesRequestWithManualMessageFetching:(BOOL)enableManualMessageFetching
{
    NSString *path = [textSecureAccountsAPI stringByAppendingString:textSecureAttributesAPI];
    NSString *_Nullable pin = [OWS2FAManager.sharedManager pinCode];
    return [TSRequest
        requestWithUrl:[NSURL URLWithString:path]
                method:@"PUT"
            parameters:[TSAttributes attributesFromStorageWithManualMessageFetching:enableManualMessageFetching
                                                                                pin:pin]];
}

+ (TSRequest *)unregisterAccountRequest
{
    NSString *path = [NSString stringWithFormat:@"%@/%@", textSecureAccountsAPI, @"apn"];
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"DELETE" parameters:@{}];
}

+ (TSRequest *)requestVerificationCodeRequestWithPhoneNumber:(NSString *)phoneNumber
                                                   transport:(TSVerificationTransport)transport
{
    OWSAssertDebug(phoneNumber.length > 0);
    NSString *path = [NSString stringWithFormat:@"%@/%@/code/%@?client=ios",
                               textSecureAccountsAPI,
                               [self stringForTransport:transport],
                               phoneNumber];
    TSRequest *request = [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
    request.shouldHaveAuthorizationHeaders = NO;
    return request;
}

+ (NSString *)stringForTransport:(TSVerificationTransport)transport
{
    switch (transport) {
        case TSVerificationTransportSMS:
            return @"sms";
        case TSVerificationTransportVoice:
            return @"voice";
    }
}

+ (TSRequest *)submitMessageRequestWithRecipient:(NSString *)recipientId
                                        messages:(NSArray *)messages
                                       timeStamp:(uint64_t)timeStamp
{
    // NOTE: messages may be empty; See comments in OWSDeviceManager.
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug(timeStamp > 0);

    NSString *path = [textSecureMessagesAPI stringByAppendingString:recipientId];
    NSDictionary *parameters = @{
        @"messages" : messages,
        @"timestamp" : @(timeStamp),
    };

    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"PUT" parameters:parameters];
}

+ (TSRequest *)registerSignedPrekeyRequestWithSignedPreKeyRecord:(SignedPreKeyRecord *)signedPreKey
{
    OWSAssertDebug(signedPreKey);

    NSString *path = textSecureSignedKeysAPI;
    return [TSRequest requestWithUrl:[NSURL URLWithString:path]
                              method:@"PUT"
                          parameters:[self dictionaryFromSignedPreKey:signedPreKey]];
}

+ (TSRequest *)registerPrekeysRequestWithPrekeyArray:(NSArray *)prekeys
                                         identityKey:(NSData *)identityKeyPublic
                                        signedPreKey:(SignedPreKeyRecord *)signedPreKey
{
    OWSAssertDebug(prekeys.count > 0);
    OWSAssertDebug(identityKeyPublic.length > 0);
    OWSAssertDebug(signedPreKey);

    NSString *path = textSecureKeysAPI;
    NSString *publicIdentityKey = [[identityKeyPublic prependKeyType] base64EncodedStringWithOptions:0];
    NSMutableArray *serializedPrekeyList = [NSMutableArray array];
    for (PreKeyRecord *preKey in prekeys) {
        [serializedPrekeyList addObject:[self dictionaryFromPreKey:preKey]];
    }
    return [TSRequest requestWithUrl:[NSURL URLWithString:path]
                              method:@"PUT"
                          parameters:@{
                              @"preKeys" : serializedPrekeyList,
                              @"signedPreKey" : [self dictionaryFromSignedPreKey:signedPreKey],
                              @"identityKey" : publicIdentityKey
                          }];
}

+ (NSDictionary *)dictionaryFromPreKey:(PreKeyRecord *)preKey
{
    return @{
        @"keyId" : @(preKey.Id),
        @"publicKey" : [[preKey.keyPair.publicKey prependKeyType] base64EncodedStringWithOptions:0],
    };
}

+ (NSDictionary *)dictionaryFromSignedPreKey:(SignedPreKeyRecord *)preKey
{
    return @{
        @"keyId" : @(preKey.Id),
        @"publicKey" : [[preKey.keyPair.publicKey prependKeyType] base64EncodedStringWithOptions:0],
        @"signature" : [preKey.signature base64EncodedStringWithOptions:0]
    };
}

+ (TSRequest *)remoteAttestationRequest:(ECKeyPair *)keyPair
                              enclaveId:(NSString *)enclaveId
                           authUsername:(NSString *)authUsername
                           authPassword:(NSString *)authPassword
{
    OWSAssertDebug(keyPair);
    OWSAssertDebug(enclaveId.length > 0);
    OWSAssertDebug(authUsername.length > 0);
    OWSAssertDebug(authPassword.length > 0);

    NSString *path = [NSString stringWithFormat:@"%@/v1/attestation/%@", contactDiscoveryURL, enclaveId];
    TSRequest *request = [TSRequest requestWithUrl:[NSURL URLWithString:path]
                                            method:@"PUT"
                                        parameters:@{
                                            // We DO NOT prepend the "key type" byte.
                                            @"clientPublic" : [keyPair.publicKey base64EncodedStringWithOptions:0],
                                        }];
    request.authUsername = authUsername;
    request.authPassword = authPassword;

    // Don't bother with the default cookie store;
    // these cookies are ephemeral.
    [request setHTTPShouldHandleCookies:NO];

    return request;
}

+ (TSRequest *)enclaveContactDiscoveryRequestWithId:(NSData *)requestId
                                       addressCount:(NSUInteger)addressCount
                               encryptedAddressData:(NSData *)encryptedAddressData
                                            cryptIv:(NSData *)cryptIv
                                           cryptMac:(NSData *)cryptMac
                                          enclaveId:(NSString *)enclaveId
                                       authUsername:(NSString *)authUsername
                                       authPassword:(NSString *)authPassword
                                            cookies:(NSArray<NSHTTPCookie *> *)cookies
{
    NSString *path = [NSString stringWithFormat:@"%@/v1/discovery/%@", contactDiscoveryURL, enclaveId];

    TSRequest *request = [TSRequest requestWithUrl:[NSURL URLWithString:path]
                                            method:@"PUT"
                                        parameters:@{
                                            @"requestId" : requestId.base64EncodedString,
                                            @"addressCount" : @(addressCount),
                                            @"data" : encryptedAddressData.base64EncodedString,
                                            @"iv" : cryptIv.base64EncodedString,
                                            @"mac" : cryptMac.base64EncodedString,
                                        }];

    request.authUsername = authUsername;
    request.authPassword = authPassword;

    // Don't bother with the default cookie store;
    // these cookies are ephemeral.
    [request setHTTPShouldHandleCookies:NO];
    // Set the cookie header.
    OWSAssertDebug(request.allHTTPHeaderFields.count == 0);
    [request setAllHTTPHeaderFields:[NSHTTPCookie requestHeaderFieldsWithCookies:cookies]];

    return request;
}

+ (TSRequest *)remoteAttestationAuthRequest
{
    NSString *path = @"/v1/directory/auth";
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
}

+ (TSRequest *)cdsFeedbackRequestWithResult:(NSString *)result
{
    NSString *path = [NSString stringWithFormat:@"/v1/directory/feedback/%@", result];
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"PUT" parameters:@{}];
}

#pragma mark - UD

+ (TSRequest *)udServerCertificateRequest
{
    NSString *path = @"/v1/certificate/delivery";
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
}

@end

NS_ASSUME_NONNULL_END
