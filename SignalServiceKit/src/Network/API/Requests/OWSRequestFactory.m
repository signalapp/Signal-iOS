//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "OWSRequestFactory.h"
#import "NSData+keyVersionByte.h"
#import "OWS2FAManager.h"
#import "OWSDevice.h"
#import "OWSIdentityManager.h"
#import "ProfileManagerProtocol.h"
#import "RemoteAttestation.h"
#import "SSKEnvironment.h"
#import "SignedPrekeyRecord.h"
#import "TSAccountManager.h"
#import "TSConstants.h"
#import "TSRequest.h"
#import <Curve25519Kit/Curve25519.h>
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalMetadataKit/SignalMetadataKit-Swift.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSRequestKey_AuthKey = @"AuthKey";

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

+ (TSRequest *)enableRegistrationLockV2RequestWithToken:(NSString *)token
{
    OWSAssertDebug(token.length > 0);

    return [TSRequest requestWithUrl:[NSURL URLWithString:textSecureRegistrationLockV2API]
                              method:@"PUT"
                          parameters:@{
                                       @"registrationLock" : token,
                                       }];
}

+ (TSRequest *)disableRegistrationLockV2Request
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:textSecureRegistrationLockV2API] method:@"DELETE" parameters:@{}];
}

+ (TSRequest *)acknowledgeMessageDeliveryRequestWithAddress:(SignalServiceAddress *)address timestamp:(UInt64)timestamp
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(timestamp > 0);

    NSString *path = [NSString stringWithFormat:@"v1/messages/%@/%llu", address.serviceIdentifier, timestamp];

    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"DELETE" parameters:@{}];
}

+ (TSRequest *)acknowledgeMessageDeliveryRequestWithServerGuid:(NSString *)serverGuid
{
    OWSAssertDebug(serverGuid.length > 0);

    NSString *path = [NSString stringWithFormat:@"v1/messages/uuid/%@", serverGuid];

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

+ (TSRequest *)getUnversionedProfileRequestWithAddress:(SignalServiceAddress *)address
                                           udAccessKey:(nullable SMKUDAccessKey *)udAccessKey
{
    OWSAssertDebug(address.isValid);

    NSString *path = [NSString stringWithFormat:@"v1/profile/%@", address.serviceIdentifier];
    TSRequest *request = [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
    if (udAccessKey != nil) {
        [self useUDAuthWithRequest:request accessKey:udAccessKey];
    }
    return request;
}

+ (TSRequest *)getVersionedProfileRequestWithAddress:(SignalServiceAddress *)address
                                   profileKeyVersion:(nullable NSString *)profileKeyVersion
                                   credentialRequest:(nullable NSData *)credentialRequest
                                         udAccessKey:(nullable SMKUDAccessKey *)udAccessKey
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(address.uuid != nil);

    NSString *uuidParam = address.uuid.UUIDString.lowercaseString;
    NSString *_Nullable profileKeyVersionParam = profileKeyVersion.lowercaseString;
    NSString *_Nullable credentialRequestParam = credentialRequest.hexadecimalString.lowercaseString;

    // GET /v1/profile/{uuid}/{version}/{profile_key_credential_request}
    NSString *path;
    if (profileKeyVersion.length > 0 && credentialRequest.length > 0) {
        path = [NSString stringWithFormat:@"v1/profile/%@/%@/%@",
                         uuidParam,
                         profileKeyVersionParam,
                         credentialRequestParam];
    } else if (profileKeyVersion.length > 0) {
        path = [NSString stringWithFormat:@"v1/profile/%@/%@", uuidParam, profileKeyVersionParam];
    } else {
        path = [NSString stringWithFormat:@"v1/profile/%@", uuidParam];
    }

    TSRequest *request = [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
    if (udAccessKey != nil) {
        [self useUDAuthWithRequest:request accessKey:udAccessKey];
    }
    return request;
}

+ (TSRequest *)turnServerInfoRequest
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:@"v1/accounts/turn"] method:@"GET" parameters:@{}];
}

+ (TSRequest *)allocAttachmentRequestV2
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:@"v2/attachments/form/upload"] method:@"GET" parameters:@{}];
}

+ (TSRequest *)allocAttachmentRequestV3
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:@"v3/attachments/form/upload"] method:@"GET" parameters:@{}];
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

+ (TSRequest *)recipientPreKeyRequestWithAddress:(SignalServiceAddress *)address
                                        deviceId:(NSString *)deviceId
                                     udAccessKey:(nullable SMKUDAccessKey *)udAccessKey
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(deviceId.length > 0);

    NSString *path = [NSString stringWithFormat:@"%@/%@/%@", textSecureKeysAPI, address.serviceIdentifier, deviceId];

    TSRequest *request = [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
    if (udAccessKey != nil) {
        [self useUDAuthWithRequest:request accessKey:udAccessKey];
    }
    return request;
}

+ (TSRequest *)registerForPushRequestWithPushIdentifier:(NSString *)identifier
                                         voipIdentifier:(nullable NSString *)voipId
{
    OWSAssertDebug(identifier.length > 0);

    NSString *path = [NSString stringWithFormat:@"%@/%@", textSecureAccountsAPI, @"apn"];

    NSMutableDictionary *parameters = [@{ @"apnRegistrationId" : identifier } mutableCopy];
    if (voipId.length > 0) {
        parameters[@"voipRegistrationId"] = voipId;
    } else {
        OWSAssertDebug(SSKFeatureFlags.notificationServiceExtension);
    }

    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"PUT" parameters:parameters];
}

+ (TSRequest *)updatePrimaryDeviceAttributesRequest
{
    // If you are updating capabilities for a secondary device, use `updateSecondaryDeviceCapabilities` instead
    OWSAssertDebug(self.tsAccountManager.isPrimaryDevice);
    NSString *authKey = self.tsAccountManager.storedServerAuthToken;
    OWSAssertDebug(authKey.length > 0);
    NSString *_Nullable pin = [self.ows2FAManager pinCode];
    BOOL isManualMessageFetchEnabled = self.tsAccountManager.isManualMessageFetchEnabled;

    NSDictionary<NSString *, id> *accountAttributes = [self accountAttributesWithAuthKey:authKey
                                                                                     pin:pin
                                                                     encryptedDeviceName:nil
                                                             isManualMessageFetchEnabled:isManualMessageFetchEnabled
                                                                       isSecondaryDevice:NO];

    return [TSRequest requestWithUrl:[NSURL URLWithString:textSecureAttributesAPI]
                              method:@"PUT"
                          parameters:accountAttributes];
}

+ (TSRequest *)accountWhoAmIRequest
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:@"v1/accounts/whoami"] method:@"GET" parameters:@{}];
}

+ (TSRequest *)unregisterAccountRequest
{
    NSString *path = [NSString stringWithFormat:@"%@/%@", textSecureAccountsAPI, @"me"];
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"DELETE" parameters:@{}];
}

+ (TSRequest *)requestPreauthChallengeRequestWithRecipientId:(NSString *)recipientId
                                                   pushToken:(NSString *)pushToken
                                                 isVoipToken:(BOOL)isVoipToken
{
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug(pushToken.length > 0);

    NSString *path = [NSString stringWithFormat:@"v1/accounts/apn/preauth/%@/%@?voip=%@",
                               pushToken,
                               recipientId,
                               isVoipToken ? @"true" : @"false"];
    NSURL *url = [NSURL URLWithString:path];

    TSRequest *request = [TSRequest requestWithUrl:url method:@"GET" parameters:@{}];
    request.shouldHaveAuthorizationHeaders = NO;

    return request;
}

+ (TSRequest *)requestVerificationCodeRequestWithPhoneNumber:(NSString *)phoneNumber
                                            preauthChallenge:(nullable NSString *)preauthChallenge
                                                captchaToken:(nullable NSString *)captchaToken
                                                   transport:(TSVerificationTransport)transport
{
    OWSAssertDebug(phoneNumber.length > 0);

    NSMutableArray<NSURLQueryItem *> *queryItems = [NSMutableArray new];
    [queryItems addObject:[NSURLQueryItem queryItemWithName:@"client" value:@"ios"]];

    if (captchaToken.length > 0) {
        [queryItems addObject:[NSURLQueryItem queryItemWithName:@"captcha" value:captchaToken]];
    }

    if (preauthChallenge.length > 0) {
        [queryItems addObject:[NSURLQueryItem queryItemWithName:@"challenge" value:preauthChallenge]];
    }

    NSString *path = [NSString
        stringWithFormat:@"%@/%@/code/%@", textSecureAccountsAPI, [self stringForTransport:transport], phoneNumber];

    NSURLComponents *components = [[NSURLComponents alloc] initWithString:path];
    components.queryItems = queryItems;

    TSRequest *request = [TSRequest requestWithUrl:components.URL method:@"GET" parameters:@{}];
    request.shouldHaveAuthorizationHeaders = NO;

    if (transport == TSVerificationTransportVoice) {
        NSString *_Nullable localizationHeader = [self voiceCodeLocalizationHeader];
        if (localizationHeader.length > 0) {
            [request setValue:localizationHeader forHTTPHeaderField:@"Accept-Language"];
        }
    }

    return request;
}

+ (nullable NSString *)voiceCodeLocalizationHeader
{
    NSLocale *locale = [NSLocale currentLocale];
    NSString *_Nullable languageCode = [locale objectForKey:NSLocaleLanguageCode];
    NSString *_Nullable countryCode = [locale objectForKey:NSLocaleCountryCode];

    if (!languageCode) {
        return nil;
    }

    OWSAssertDebug([languageCode rangeOfString:@"-"].location == NSNotFound);

    if (!countryCode) {
        // In the absence of a country code, just send a language code.
        return languageCode;
    }

    OWSAssertDebug(languageCode.length == 2);
    OWSAssertDebug(countryCode.length == 2);
    return [NSString stringWithFormat:@"%@-%@", languageCode, countryCode];
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

+ (TSRequest *)verifyPrimaryDeviceRequestWithVerificationCode:(NSString *)verificationCode
                                                  phoneNumber:(NSString *)phoneNumber
                                                      authKey:(NSString *)authKey
                                                          pin:(nullable NSString *)pin
                                    checkForAvailableTransfer:(BOOL)checkForAvailableTransfer
{
    OWSAssertDebug(verificationCode.length > 0);
    OWSAssertDebug(phoneNumber.length > 0);
    OWSAssertDebug(authKey.length > 0);

    NSString *path = [NSString stringWithFormat:@"%@/code/%@", textSecureAccountsAPI, verificationCode];

    if (checkForAvailableTransfer) {
        path = [path stringByAppendingString:@"?transfer=true"];
    }

    BOOL isManualMessageFetchEnabled = self.tsAccountManager.isManualMessageFetchEnabled;
    NSMutableDictionary<NSString *, id> *accountAttributes =
        [[self accountAttributesWithAuthKey:authKey
                                        pin:pin
                        encryptedDeviceName:nil
                isManualMessageFetchEnabled:isManualMessageFetchEnabled
                          isSecondaryDevice:NO] mutableCopy];
    [accountAttributes removeObjectForKey:OWSRequestKey_AuthKey];

    TSRequest *request =
        [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"PUT" parameters:accountAttributes];
    // The "verify code" request handles auth differently.
    request.authUsername = phoneNumber;
    request.authPassword = authKey;
    return request;
}

+ (TSRequest *)verifySecondaryDeviceRequestWithVerificationCode:(NSString *)verificationCode
                                                    phoneNumber:(NSString *)phoneNumber
                                                        authKey:(NSString *)authKey
                                            encryptedDeviceName:(NSData *)encryptedDeviceName
{
    OWSAssertDebug(verificationCode.length > 0);
    OWSAssertDebug(phoneNumber.length > 0);
    OWSAssertDebug(authKey.length > 0);
    OWSAssertDebug(encryptedDeviceName.length > 0);

    NSString *path = [NSString stringWithFormat:@"v1/devices/%@", verificationCode];

    NSMutableDictionary<NSString *, id> *accountAttributes = [[self accountAttributesWithAuthKey:authKey
                                                                                             pin:nil
                                                                             encryptedDeviceName:encryptedDeviceName
                                                                     isManualMessageFetchEnabled:YES
                                                                               isSecondaryDevice:YES] mutableCopy];

    [accountAttributes removeObjectForKey:OWSRequestKey_AuthKey];

    TSRequest *request = [TSRequest requestWithUrl:[NSURL URLWithString:path]
                                            method:@"PUT"
                                        parameters:accountAttributes];
    // The "verify code" request handles auth differently.
    request.authUsername = phoneNumber;
    request.authPassword = authKey;
    return request;
}

+ (TSRequest *)currencyConversionRequest NS_SWIFT_NAME(currencyConversionRequest())
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:@"v1/payments/conversions"] method:@"GET" parameters:@{}];
}

+ (NSDictionary<NSString *, id> *)accountAttributesWithAuthKey:(NSString *)authKey
                                                           pin:(nullable NSString *)pin
                                           encryptedDeviceName:(nullable NSData *)encryptedDeviceName
                                   isManualMessageFetchEnabled:(BOOL)isManualMessageFetchEnabled
                                             isSecondaryDevice:(BOOL)isSecondaryDevice
{
    OWSAssertDebug(authKey.length > 0);
    uint32_t registrationId = [self.tsAccountManager getOrGenerateRegistrationId];

    OWSAES256Key *profileKey = [self.profileManager localProfileKey];
    NSError *error;
    SMKUDAccessKey *_Nullable udAccessKey = [[SMKUDAccessKey alloc] initWithProfileKey:profileKey.keyData error:&error];
    if (error || udAccessKey.keyData.length < 1) {
        // Crash app if UD cannot be enabled.
        OWSFail(@"Could not determine UD access key: %@.", error);
    }
    BOOL allowUnrestrictedUD = [self.udManager shouldAllowUnrestrictedAccessLocal] && udAccessKey != nil;

    // We no longer include the signalingKey.
    NSMutableDictionary *accountAttributes = [@{
        OWSRequestKey_AuthKey : authKey,
        @"voice" : @(YES), // all Signal-iOS clients support voice
        @"video" : @(YES), // all Signal-iOS clients support WebRTC-based voice and video calls.
        @"fetchesMessages" : @(isManualMessageFetchEnabled), // devices that don't support push must tell the server
                                                             // they fetch messages manually
        @"registrationId" : [NSString stringWithFormat:@"%i", registrationId],
        @"unidentifiedAccessKey" : udAccessKey.keyData.base64EncodedString,
        @"unrestrictedUnidentifiedAccess" : @(allowUnrestrictedUD),
    } mutableCopy];

    NSString *_Nullable registrationLockToken = [OWSKeyBackupService deriveRegistrationLockToken];
    if (registrationLockToken.length > 0 && OWS2FAManager.shared.isRegistrationLockV2Enabled) {
        accountAttributes[@"registrationLock"] = registrationLockToken;
    } else if (pin.length > 0 && self.ows2FAManager.mode != OWS2FAMode_V2) {
        accountAttributes[@"pin"] = pin;
    }

    if (encryptedDeviceName.length > 0) {
        accountAttributes[@"name"] = encryptedDeviceName.base64EncodedString;
    }

    if (SSKFeatureFlags.phoneNumberDiscoverability) {
        accountAttributes[@"discoverableByPhoneNumber"] = @(self.tsAccountManager.isDiscoverableByPhoneNumber);
    }

    accountAttributes[@"capabilities"] = [self deviceCapabilitiesWithIsSecondaryDevice:isSecondaryDevice];

    return [accountAttributes copy];
}

+ (TSRequest *)updateSecondaryDeviceCapabilitiesRequest
{
    // If you are updating capabilities for a primary device, use `updateAccountAttributes` instead
    OWSAssertDebug(!self.tsAccountManager.isPrimaryDevice);

    return [TSRequest requestWithUrl:[NSURL URLWithString:@"v1/devices/capabilities"]
                              method:@"PUT"
                          parameters:[self deviceCapabilitiesWithIsSecondaryDevice:YES]];
}

+ (NSDictionary<NSString *, NSNumber *> *)deviceCapabilitiesForLocalDevice
{
    // tsAccountManager.isPrimaryDevice only has a valid value for registered
    // devices.
    OWSAssertDebug(self.tsAccountManager.isRegisteredAndReady);

    BOOL isSecondaryDevice = !self.tsAccountManager.isPrimaryDevice;
    return [self deviceCapabilitiesWithIsSecondaryDevice:isSecondaryDevice];
}

+ (NSDictionary<NSString *, NSNumber *> *)deviceCapabilitiesWithIsSecondaryDevice:(BOOL)isSecondaryDevice
{
    NSMutableDictionary<NSString *, NSNumber *> *capabilities = [NSMutableDictionary new];
    capabilities[@"gv2"] = @(YES);
    capabilities[@"gv2-2"] = @(YES);
    capabilities[@"gv2-3"] = @(YES);
    capabilities[@"transfer"] = @(YES);
    capabilities[@"announcementGroup"] = @(YES);
    capabilities[@"gv1-migration"] = @(YES);
    capabilities[@"senderKey"] = @(YES);

    // If the storage service requires (or will require) secondary devices
    // to have a capability in order to be linked, we might need to always
    // set that capability here if isSecondaryDevice is true.

    if (OWSKeyBackupService.hasBackedUpMasterKey) {
        capabilities[@"storage"] = @(YES);
    }

    OWSLogInfo(@"local device capabilities: %@", capabilities);
    return [capabilities copy];
}

+ (TSRequest *)submitMessageRequestWithAddress:(SignalServiceAddress *)recipientAddress
                                      messages:(NSArray *)messages
                                     timeStamp:(uint64_t)timeStamp
                                   udAccessKey:(nullable SMKUDAccessKey *)udAccessKey
                                      isOnline:(BOOL)isOnline
{
    // NOTE: messages may be empty; See comments in OWSDeviceManager.
    OWSAssertDebug(recipientAddress.isValid);
    OWSAssertDebug(timeStamp > 0);

    NSString *path = [textSecureMessagesAPI stringByAppendingString:recipientAddress.serviceIdentifier];

    // Returns the per-account-message parameters used when submitting a message to
    // the Signal Web Service.
    // See: https://github.com/signalapp/Signal-Server/blob/master/service/src/main/java/org/whispersystems/textsecuregcm/entities/IncomingMessageList.java
    NSDictionary *parameters = @{ @"messages" : messages, @"timestamp" : @(timeStamp), @"online" : @(isOnline) };

    TSRequest *request = [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"PUT" parameters:parameters];
    if (udAccessKey != nil) {
        [self useUDAuthWithRequest:request accessKey:udAccessKey];
    }
    return request;
}

+ (TSRequest *)submitMultiRecipientMessageRequestWithCiphertext:(NSData *)ciphertext
                                           compositeUDAccessKey:(SMKUDAccessKey *)udAccessKey
                                                      timestamp:(uint64_t)timestamp
                                                       isOnline:(BOOL)isOnline
{
    OWSAssertDebug(ciphertext);
    OWSAssertDebug(udAccessKey);
    OWSAssertDebug(timestamp > 0);

    // We build the URL by hand instead of passing the query parameters into the query parameters
    // AFNetworking won't handle both query parameters and an httpBody (which we need here)
    NSURLComponents *components = [[NSURLComponents alloc] initWithString:textSecureMultiRecipientMessageAPI];
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"ts" value:[@(timestamp) stringValue]],
        [NSURLQueryItem queryItemWithName:@"online" value:isOnline ? @"true" : @"false"],
    ];
    NSURL *url = [components URL];

    TSRequest *request = [TSRequest requestWithUrl:url method:@"PUT" parameters:nil];
    [request setValue:kSenderKeySendRequestBodyContentType forHTTPHeaderField:@"Content-Type"];
    if (udAccessKey != nil) {
        [self useUDAuthWithRequest:request accessKey:udAccessKey];
    }
    request.HTTPBody = [ciphertext copy];
    return request;
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

#pragma mark - Storage Service

+ (TSRequest *)storageAuthRequest
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:@"v1/storage/auth"] method:@"GET" parameters:@{}];
}

#pragma mark - Remote Attestation

+ (TSRequest *)remoteAttestationAuthRequestForService:(RemoteAttestationService)service
{
    NSString *path;
    switch (service) {
        case RemoteAttestationServiceContactDiscovery:
            path = @"v1/directory/auth";
            break;
        case RemoteAttestationServiceKeyBackup:
            path = @"v1/backup/auth";
            break;
    }
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
}

#pragma mark - CDS

+ (TSRequest *)cdsFeedbackRequestWithStatus:(NSString *)status
                                     reason:(nullable NSString *)reason
{

    NSDictionary<NSString *, NSString *> *parameters;
    if (reason == nil) {
        parameters = @{};
    } else {
        const NSUInteger kServerReasonLimit = 1000;
        NSString *limitedReason;
        if (reason.length < kServerReasonLimit) {
            limitedReason = reason;
        } else {
            OWSFailDebug(@"failure: reason should be under 1000");
            limitedReason = [reason substringToIndex:kServerReasonLimit - 1];
        }
        parameters = @{ @"reason": limitedReason };
    }
    NSString *path = [NSString stringWithFormat:@"v1/directory/feedback-v3/%@", status];
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"PUT" parameters:parameters];
}

#pragma mark - KBS

+ (TSRequest *)kbsEnclaveTokenRequestWithEnclaveName:(NSString *)enclaveName
                                        authUsername:(NSString *)authUsername
                                        authPassword:(NSString *)authPassword
                                             cookies:(NSArray<NSHTTPCookie *> *)cookies
{
    NSString *path = [NSString stringWithFormat:@"v1/token/%@", enclaveName];

    TSRequest *request = [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];

    request.authUsername = authUsername;
    request.authPassword = authPassword;

    // Set the cookie header.
    // OWSURLSession disables default cookie handling for all requests.
    OWSAssertDebug(request.allHTTPHeaderFields.count == 0);
    [request setAllHTTPHeaderFields:[NSHTTPCookie requestHeaderFieldsWithCookies:cookies]];

    return request;
}

+ (TSRequest *)kbsEnclaveRequestWithRequestId:(NSData *)requestId
                                         data:(NSData *)data
                                      cryptIv:(NSData *)cryptIv
                                     cryptMac:(NSData *)cryptMac
                                  enclaveName:(NSString *)enclaveName
                                 authUsername:(NSString *)authUsername
                                 authPassword:(NSString *)authPassword
                                      cookies:(NSArray<NSHTTPCookie *> *)cookies
                                  requestType:(NSString *)requestType
{
    NSString *path = [NSString stringWithFormat:@"v1/backup/%@", enclaveName];

    TSRequest *request = [TSRequest requestWithUrl:[NSURL URLWithString:path]
                                            method:@"PUT"
                                        parameters:@{
                                            @"requestId" : requestId.base64EncodedString,
                                            @"data" : data.base64EncodedString,
                                            @"iv" : cryptIv.base64EncodedString,
                                            @"mac" : cryptMac.base64EncodedString,
                                            @"type" : requestType
                                        }];

    request.authUsername = authUsername;
    request.authPassword = authPassword;

    // Set the cookie header.
    // OWSURLSession disables default cookie handling for all requests.
    OWSAssertDebug(request.allHTTPHeaderFields.count == 0);
    [request setAllHTTPHeaderFields:[NSHTTPCookie requestHeaderFieldsWithCookies:cookies]];

    return request;
}

#pragma mark - UD

+ (TSRequest *)udSenderCertificateRequestWithUuidOnly:(BOOL)uuidOnly
{
    NSString *path = @"v1/certificate/delivery?includeUuid=true";
    if (uuidOnly) {
        path = [path stringByAppendingString:@"&includeE164=false"];
    }
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
}

+ (void)useUDAuthWithRequest:(TSRequest *)request accessKey:(SMKUDAccessKey *)udAccessKey
{
    OWSAssertDebug(request);
    OWSAssertDebug(udAccessKey);

    // Suppress normal auth headers.
    request.shouldHaveAuthorizationHeaders = NO;

    // Add UD auth header.
    [request setValue:[udAccessKey.keyData base64EncodedString] forHTTPHeaderField:@"Unidentified-Access-Key"];

    request.isUDRequest = YES;
}

#pragma mark - Usernames

+ (TSRequest *)usernameSetRequest:(NSString *)username
{
    OWSAssertDebug(username.length > 0);

    NSString *path = [NSString stringWithFormat:@"v1/accounts/username/%@", username];
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"PUT" parameters:@{}];
}

+ (TSRequest *)usernameDeleteRequest
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:@"v1/accounts/username"] method:@"DELETE" parameters:@{}];
}

+ (TSRequest *)getProfileRequestWithUsername:(NSString *)username
{
    OWSAssertDebug(username.length > 0);
    
    NSString *urlEncodedUsername =
    [username stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLUserAllowedCharacterSet]];
    
    OWSAssertDebug(urlEncodedUsername.length > 0);
    
    NSString *path = [NSString stringWithFormat:@"v1/profile/username/%@", urlEncodedUsername];
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
}

#pragma mark - Profiles

+ (TSRequest *)profileNameSetRequestWithEncryptedPaddedName:(NSData *)encryptedPaddedName
{
    const NSUInteger kEncodedNameLength = 108;

    NSString *base64EncodedName = [encryptedPaddedName base64EncodedString];
    NSString *urlEncodedName;
    // name length must match exactly
    if (base64EncodedName.length == kEncodedNameLength) {
        urlEncodedName = base64EncodedName.encodeURIComponent;
    } else {
        // if name length doesn't match exactly, use a blank name.
        // Since names are required, the server will reject this with HTTP405,
        // which is desirable - we want this request to fail rather than upload
        // a broken name.
        OWSFailDebug(@"Couldn't encode name.");
        OWSAssertDebug(encryptedPaddedName == nil);
        urlEncodedName = @"";
    }
    NSString *urlString = [NSString stringWithFormat:@"v1/profile/name/%@", urlEncodedName];

    NSURL *url = [NSURL URLWithString:urlString];
    TSRequest *request = [[TSRequest alloc] initWithURL:url];
    request.HTTPMethod = @"PUT";
    
    return request;
}

#pragma mark - Versioned Profiles

+ (TSRequest *)versionedProfileSetRequestWithName:(nullable ProfileValue *)name
                                              bio:(nullable ProfileValue *)bio
                                         bioEmoji:(nullable ProfileValue *)bioEmoji
                                        hasAvatar:(BOOL)hasAvatar
                                   paymentAddress:(nullable ProfileValue *)paymentAddress
                                  visibleBadgeIds:(NSArray<NSString *> *)visibleBadgeIds
                                          version:(NSString *)version
                                       commitment:(NSData *)commitment
{
    OWSAssertDebug(version.length > 0);
    OWSAssertDebug(commitment.length > 0);

    NSString *base64EncodedCommitment = [commitment base64EncodedString];

    NSMutableDictionary<NSString *, NSObject *> *parameters = [@{
        @"version" : version,
        @"avatar" : @(hasAvatar),
        @"commitment" : base64EncodedCommitment,
    } mutableCopy];

    if (name != nil) {
        OWSAssertDebug(name.hasValidBase64Length);
        parameters[@"name"] = name.encryptedBase64;
    }
    if (bio != nil) {
        OWSAssertDebug(bio.hasValidBase64Length);
        parameters[@"about"] = bio.encryptedBase64;
    }
    if (bioEmoji != nil) {
        OWSAssertDebug(bioEmoji.hasValidBase64Length);
        parameters[@"aboutEmoji"] = bioEmoji.encryptedBase64;
    }
    if (paymentAddress != nil) {
        OWSAssertDebug(paymentAddress.hasValidBase64Length);
        parameters[@"paymentAddress"] = paymentAddress.encryptedBase64;
    }
    parameters[@"badgeIds"] = [visibleBadgeIds copy];

    NSURL *url = [NSURL URLWithString:textSecureVersionedProfileAPI];
    return [TSRequest requestWithUrl:url
                              method:@"PUT"
                          parameters:parameters];
}

#pragma mark - Remote Config

+ (TSRequest *)getRemoteConfigRequest
{
    NSURL *url = [NSURL URLWithString:@"/v1/config/"];
    return [TSRequest requestWithUrl:url method:@"GET" parameters:@{}];
}

#pragma mark - Groups v2

+ (TSRequest *)groupAuthenticationCredentialRequestWithFromRedemptionDays:(uint32_t)fromRedemptionDays
                                                         toRedemptionDays:(uint32_t)toRedemptionDays
{
    OWSAssertDebug(fromRedemptionDays > 0);
    OWSAssertDebug(toRedemptionDays > 0);

    NSString *path = [NSString stringWithFormat:@"/v1/certificate/group/%lu/%lu",
                               (unsigned long)fromRedemptionDays,
                               (unsigned long)toRedemptionDays];
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
}

#pragma mark - Payments

+ (TSRequest *)paymentsAuthenticationCredentialRequest
{
    NSString *path = @"/v1/payments/auth";
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
}

#pragma mark - Spam

+ (TSRequest *)pushChallengeRequest
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:@"/v1/challenge/push"] method:@"POST" parameters:@{}];
}

+ (TSRequest *)pushChallengeResponseWithToken:(NSString *)challengeToken
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:@"/v1/challenge"]
                              method:@"PUT"
                          parameters:@{ @"type" : @"rateLimitPushChallenge", @"challenge" : challengeToken }];
}

+ (TSRequest *)recaptchChallengeResponseWithToken:(NSString *)serverToken captchaToken:(NSString *)captchaToken
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:@"/v1/challenge"]
                              method:@"PUT"
                          parameters:@{ @"type" : @"recaptcha", @"token" : serverToken, @"captcha" : captchaToken }];
}

+ (TSRequest *)reportSpamFromPhoneNumber:(NSString *)phoneNumber withServerGuid:(NSString *)serverGuid
{
    OWSAssertDebug(phoneNumber.length > 0);
    OWSAssertDebug(serverGuid.length > 0);

    NSString *path = [NSString stringWithFormat:@"/v1/messages/report/%@/%@", phoneNumber, serverGuid];
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"POST" parameters:@{}];
}

#pragma mark - Donations

+ (TSRequest *)createPaymentIntentWithAmount:(NSUInteger)amount
                              inCurrencyCode:(NSString *)currencyCode
                             withDescription:(nullable NSString *)description
{
    NSMutableDictionary *parameters =
        [@{ @"currency" : currencyCode.lowercaseString, @"amount" : @(amount) } mutableCopy];
    if (description) {
        parameters[@"description"] = description;
    }

    return [TSRequest requestWithUrl:[NSURL URLWithString:@"/v1/donation/authorize-apple-pay"]
                              method:@"POST"
                          parameters:parameters];
}

#pragma mark - Subscriptions

+ (TSRequest *)subscriptionLevelsRequest
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:@"/v1/subscription/levels"]
                              method:@"GET"
                          parameters:@{}];
}

+ (TSRequest *)setSubscriptionIDRequest:(NSString *)base64SubscriberID
{
    TSRequest *request =  [TSRequest requestWithUrl:[NSURL URLWithString:[NSString stringWithFormat:@"/v1/subscription/%@", base64SubscriberID]]
                                              method:@"PUT"
                                         parameters:@{}];
    request.shouldHaveAuthorizationHeaders = NO;
    request.shouldRedactUrlInLogs = YES;
    return request;
}

+ (TSRequest *)deleteSubscriptionIDRequest:(NSString *)base64SubscriberID
{
    TSRequest *request = [TSRequest
        requestWithUrl:[NSURL URLWithString:[NSString stringWithFormat:@"/v1/subscription/%@", base64SubscriberID]]
                method:@"DELETE"
            parameters:@{}];
    request.shouldHaveAuthorizationHeaders = NO;
    request.shouldRedactUrlInLogs = YES;
    return request;
}

+ (TSRequest *)subscriptionCreatePaymentMethodRequest:(NSString *)base64SubscriberID {
    TSRequest *request =  [TSRequest requestWithUrl:[NSURL URLWithString:[NSString stringWithFormat:@"/v1/subscription/%@/create_payment_method", base64SubscriberID]]
                                              method:@"POST"
                                         parameters:@{}];
    request.shouldHaveAuthorizationHeaders = NO;
    request.shouldRedactUrlInLogs = YES;
    return request;
}

+ (TSRequest *)subscriptionSetDefaultPaymentMethodRequest:(NSString *)base64SubscriberID paymentID:(NSString *)paymentID {
    TSRequest *request =  [TSRequest requestWithUrl:[NSURL URLWithString:[NSString stringWithFormat:@"/v1/subscription/%@/default_payment_method/%@", base64SubscriberID, paymentID]]
                                              method:@"POST"
                                         parameters:@{}];
    request.shouldHaveAuthorizationHeaders = NO;
    request.shouldRedactUrlInLogs = YES;
    return request;
}

+ (TSRequest *)subscriptionSetSubscriptionLevelRequest:(NSString *)base64SubscriberID level:(NSString *)level currency:(NSString *)currency idempotencyKey:(NSString *)idempotencyKey  {
    TSRequest *request =  [TSRequest requestWithUrl:[NSURL URLWithString:[NSString stringWithFormat:@"/v1/subscription/%@/level/%@/%@/%@", base64SubscriberID, level, currency, idempotencyKey]]
                                              method:@"PUT"
                                         parameters:@{}];
    request.shouldHaveAuthorizationHeaders = NO;
    request.shouldRedactUrlInLogs = YES;
    return request;
}

+ (TSRequest *)subscriptionRecieptCredentialsRequest:(NSString *)base64SubscriberID request:(NSString *)base64ReceiptCredentialRequest {
    TSRequest *request =  [TSRequest requestWithUrl:[NSURL URLWithString:[NSString stringWithFormat:@"/v1/subscription/%@/receipt_credentials", base64SubscriberID]]
                                              method:@"POST"
                                         parameters:@{@"receiptCredentialRequest" : base64ReceiptCredentialRequest}];
    request.shouldHaveAuthorizationHeaders = NO;
    request.shouldRedactUrlInLogs = YES;
    return request;
}

+ (TSRequest *)subscriptionRedeemRecieptCredential:(NSString *)base64ReceiptCredentialPresentation
{
    TSRequest *request = [TSRequest requestWithUrl:[NSURL URLWithString:@"/v1/donation/redeem-receipt"]
                                            method:@"POST"
                                        parameters:@{
                                            @"receiptCredentialPresentation" : base64ReceiptCredentialPresentation,
                                            @"visible" : @(self.profileManager.localProfileHasVisibleBadge),
                                            @"primary" : @(NO)
                                        }];
    return request;
}

+ (TSRequest *)subscriptionGetCurrentSubscriptionLevelRequest:(NSString *)base64SubscriberID
{
    TSRequest *request = [TSRequest
        requestWithUrl:[NSURL URLWithString:[NSString stringWithFormat:@"/v1/subscription/%@", base64SubscriberID]]
                method:@"GET"
            parameters:@{}];
    request.shouldRedactUrlInLogs = YES;
    request.shouldHaveAuthorizationHeaders = NO;
    return request;
}

+ (TSRequest *)boostSuggestedAmountsRequest
{
    TSRequest *request = [TSRequest requestWithUrl:[NSURL URLWithString:@"/v1/subscription/boost/amounts"]
                                            method:@"GET"
                                        parameters:@{}];
    request.shouldHaveAuthorizationHeaders = NO;
    return request;
}

+ (TSRequest *)boostCreatePaymentIntentWithAmount:(NSUInteger)amount
                                   inCurrencyCode:(NSString *)currencyCode
{
    TSRequest *request =
        [TSRequest requestWithUrl:[NSURL URLWithString:@"/v1/subscription/boost/create"]
                           method:@"POST"
                       parameters:@{ @"currency" : currencyCode.lowercaseString, @"amount" : @(amount) }];
    request.shouldHaveAuthorizationHeaders = NO;
    return request;
}

+ (TSRequest *)boostRecieptCredentialsWithPaymentIntentId:(NSString *)paymentIntentId
                                               andRequest:(NSString *)base64ReceiptCredentialRequest
{
    TSRequest *request = [TSRequest requestWithUrl:[NSURL URLWithString:@"/v1/subscription/boost/receipt_credentials"]
                                            method:@"POST"
                                        parameters:@{
                                            @"paymentIntentId" : paymentIntentId,
                                            @"receiptCredentialRequest" : base64ReceiptCredentialRequest
                                        }];
    request.shouldHaveAuthorizationHeaders = NO;
    return request;
}

+ (TSRequest *)boostBadgesRequest
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:@"/v1/subscription/boost/badges"]
                              method:@"GET"
                          parameters:@{}];
}

@end

NS_ASSUME_NONNULL_END
