//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSRequestFactory.h"
#import "OWS2FAManager.h"
#import "OWSDevice.h"
#import "OWSIdentityManager.h"
#import "ProfileManagerProtocol.h"
#import "RemoteAttestation.h"
#import "SSKEnvironment.h"
#import "TSAccountManager.h"
#import "TSConstants.h"
#import "TSRequest.h"
#import <AxolotlKit/NSData+keyVersionByte.h>
#import <AxolotlKit/SignedPreKeyRecord.h>
#import <Curve25519Kit/Curve25519.h>
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalMetadataKit/SignalMetadataKit-Swift.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSRequestKey_AuthKey = @"AuthKey";

@implementation OWSRequestFactory

#pragma mark - Dependencies

+ (TSAccountManager *)tsAccountManager
{
    return TSAccountManager.shared;
}

+ (OWS2FAManager *)ows2FAManager
{
    return OWS2FAManager.shared;
}

+ (id<ProfileManagerProtocol>)profileManager
{
    return SSKEnvironment.shared.profileManager;
}

+ (id<OWSUDManager>)udManager
{
    return SSKEnvironment.shared.udManager;
}

+ (OWSIdentityManager *)identityManager
{
    return SSKEnvironment.shared.identityManager;
}

#pragma mark -

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
    NSString *path = [NSString stringWithFormat:@"%@/%@", textSecureAccountsAPI, @"apn"];
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"DELETE" parameters:@{}];
}

+ (TSRequest *)requestPreauthChallengeRequestWithRecipientId:(NSString *)recipientId pushToken:(NSString *)pushToken
{
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug(pushToken.length > 0);

    NSString *path = [NSString stringWithFormat:@"v1/accounts/apn/preauth/%@/%@", pushToken, recipientId];
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

    if (SSKFeatureFlags.groupsV2MigrationSetCapability
        && !SSKDebugFlags.groupsV2migrationsDisableMigrationCapability.value) {
        capabilities[@"gv1-migration"] = @(YES);
    }

    if (OWSKeyBackupService.hasBackedUpMasterKey) {
        capabilities[@"storage"] = @(YES);
    }
    if (SSKDebugFlags.groupsV2memberStatusIndicators) {
        OWSLogInfo(@"capabilities: %@", capabilities);
    }

    capabilities[@"transfer"] = @(YES);

    return [capabilities copy];
}

+ (TSRequest *)submitMessageRequestWithAddress:(SignalServiceAddress *)recipientAddress
                                      messages:(NSArray *)messages
                                     timeStamp:(uint64_t)timeStamp
                                   udAccessKey:(nullable SMKUDAccessKey *)udAccessKey
{
    // NOTE: messages may be empty; See comments in OWSDeviceManager.
    OWSAssertDebug(recipientAddress.isValid);
    OWSAssertDebug(timeStamp > 0);

    NSString *path = [textSecureMessagesAPI stringByAppendingString:recipientAddress.serviceIdentifier];
    NSDictionary *parameters = @{
        @"messages" : messages,
        @"timestamp" : @(timeStamp),
    };

    TSRequest *request = [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"PUT" parameters:parameters];
    if (udAccessKey != nil) {
        [self useUDAuthWithRequest:request accessKey:udAccessKey];
    }
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
    request.customHost = TSConstants.keyBackupURL;
    request.customCensorshipCircumventionPrefix = TSConstants.keyBackupCensorshipPrefix;

    // Don't bother with the default cookie store;
    // these cookies are ephemeral.
    //
    // NOTE: TSNetworkManager now separately disables default cookie handling for all requests.
    [request setHTTPShouldHandleCookies:NO];
    // Set the cookie header.
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
    request.customHost = TSConstants.keyBackupURL;
    request.customCensorshipCircumventionPrefix = TSConstants.keyBackupCensorshipPrefix;

    // Don't bother with the default cookie store;
    // these cookies are ephemeral.
    //
    // NOTE: TSNetworkManager now separately disables default cookie handling for all requests.
    [request setHTTPShouldHandleCookies:NO];
    // Set the cookie header.
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

+ (TSRequest *)versionedProfileSetRequestWithName:(nullable NSData *)name
                                        hasAvatar:(BOOL)hasAvatar
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
    if (name.length > 0) {
        // TODO: Do we need check padded length as we used to with profileNameSetRequestWithEncryptedPaddedName?
        // TODO: Do we need remove "/" from name as we used to with profileNameSetRequestWithEncryptedPaddedName?

        const NSUInteger kEncodedNameLength = 108;
        NSString *base64EncodedName = [name base64EncodedString];
        OWSAssertDebug(base64EncodedName.length == kEncodedNameLength);
        parameters[@"name"] = base64EncodedName;
    }

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

@end

NS_ASSUME_NONNULL_END
