//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/OWSIdentity.h>

NS_ASSUME_NONNULL_BEGIN

@class AciObjC;
@class ChatServiceAuth;
@class DeviceMessage;
@class ECKeyPair;
@class OWSDevice;
@class PreKeyRecord;
@class SMKUDAccessKey;
@class ServiceIdObjC;
@class SignalServiceAddress;
@class SignedPreKeyRecord;
@class TSRequest;

typedef NS_ENUM(NSUInteger, TSVerificationTransport) {
    TSVerificationTransportVoice = 1,
    TSVerificationTransportSMS
};

@interface OWSRequestFactory : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

+ (TSRequest *)disable2FARequest;

+ (TSRequest *)acknowledgeMessageDeliveryRequestWithServerGuid:(NSString *)serverGuid;

+ (TSRequest *)getDevicesRequest;

+ (TSRequest *)getMessagesRequest;

+ (TSRequest *)getUnversionedProfileRequestWithServiceId:(ServiceIdObjC *)serviceId
                                             udAccessKey:(nullable SMKUDAccessKey *)udAccessKey
                                                    auth:(ChatServiceAuth *)auth
    NS_SWIFT_NAME(getUnversionedProfileRequest(serviceId:udAccessKey:auth:));

+ (TSRequest *)getVersionedProfileRequestWithAci:(AciObjC *)aci
                               profileKeyVersion:(nullable NSString *)profileKeyVersion
                               credentialRequest:(nullable NSData *)credentialRequest
                                     udAccessKey:(nullable SMKUDAccessKey *)udAccessKey
                                            auth:(ChatServiceAuth *)auth
    NS_SWIFT_NAME(getVersionedProfileRequest(aci:profileKeyVersion:credentialRequest:udAccessKey:auth:));

+ (TSRequest *)turnServerInfoRequest;

+ (TSRequest *)allocAttachmentRequestV2;

+ (TSRequest *)allocAttachmentRequestV3;

+ (TSRequest *)contactsIntersectionRequestWithHashesArray:(NSArray<NSString *> *)hashes;

+ (TSRequest *)profileAvatarUploadFormRequest;

+ (TSRequest *)registerForPushRequestWithPushIdentifier:(NSString *)identifier
                                         voipIdentifier:(nullable NSString *)voipId;

+ (TSRequest *)unregisterAccountRequest;

+ (TSRequest *)requestVerificationCodeRequestWithE164:(NSString *)e164
                                     preauthChallenge:(nullable NSString *)preauthChallenge
                                         captchaToken:(nullable NSString *)captchaToken
                                            transport:(TSVerificationTransport)transport
    NS_SWIFT_NAME(requestVerificationCodeRequest(e164:preauthChallenge:captchaToken:transport:));

+ (TSRequest *)submitMessageRequestWithServiceId:(ServiceIdObjC *)serviceId
                                        messages:(NSArray<DeviceMessage *> *)messages
                                       timestamp:(uint64_t)timestamp
                                     udAccessKey:(nullable SMKUDAccessKey *)udAccessKey
                                        isOnline:(BOOL)isOnline
                                        isUrgent:(BOOL)isUrgent
                                         isStory:(BOOL)isStory;

+ (TSRequest *)submitMultiRecipientMessageRequestWithCiphertext:(NSData *)ciphertext
                                           compositeUDAccessKey:(SMKUDAccessKey *)udAccessKey
                                                      timestamp:(uint64_t)timestamp
                                                       isOnline:(BOOL)isOnline
                                                       isUrgent:(BOOL)isUrgent
                                                        isStory:(BOOL)isStory
    NS_SWIFT_NAME(submitMultiRecipientMessageRequest(ciphertext:compositeUDAccessKey:timestamp:isOnline:isUrgent:isStory:));

+ (TSRequest *)currencyConversionRequest NS_SWIFT_NAME(currencyConversionRequest());

#pragma mark - Prekeys

+ (TSRequest *)availablePreKeysCountRequestForIdentity:(OWSIdentity)identity;

+ (TSRequest *)currentSignedPreKeyRequest;

+ (TSRequest *)recipientPreKeyRequestWithServiceId:(ServiceIdObjC *)serviceId
                                          deviceId:(uint32_t)deviceId
                                       udAccessKey:(nullable SMKUDAccessKey *)udAccessKey
                                     requestPqKeys:(BOOL)requestPqKeys;


+ (TSRequest *)registerSignedPrekeyRequestForIdentity:(OWSIdentity)identity
                                         signedPreKey:(SignedPreKeyRecord *)signedPreKey;

#pragma mark - Storage Service

+ (TSRequest *)storageAuthRequest;

#pragma mark - Remote Attestation

+ (TSRequest *)remoteAttestationAuthRequestForKeyBackup;
+ (TSRequest *)remoteAttestationAuthRequestForCDSI;
+ (TSRequest *)remoteAttestationAuthRequestForSVR2;

#pragma mark - KBS

+ (TSRequest *)kbsEnclaveTokenRequestWithEnclaveName:(NSString *)enclaveName
                                        authUsername:(NSString *)authUsername
                                        authPassword:(NSString *)authPassword
                                             cookies:(NSArray<NSHTTPCookie *> *)cookies;

+ (TSRequest *)kbsEnclaveRequestWithRequestId:(NSData *)requestId
                                         data:(NSData *)data
                                      cryptIv:(NSData *)cryptIv
                                     cryptMac:(NSData *)cryptMac
                                  enclaveName:(NSString *)enclaveName
                                 authUsername:(NSString *)authUsername
                                 authPassword:(NSString *)authPassword
                                      cookies:(NSArray<NSHTTPCookie *> *)cookies
                                  requestType:(NSString *)requestType;

#pragma mark - UD

+ (TSRequest *)udSenderCertificateRequestWithUuidOnly:(BOOL)uuidOnly
    NS_SWIFT_NAME(udSenderCertificateRequest(uuidOnly:));

#pragma mark - Profiles

+ (TSRequest *)profileNameSetRequestWithEncryptedPaddedName:(NSData *)encryptedPaddedName;

#pragma mark - Remote Config

+ (TSRequest *)getRemoteConfigRequest;

#pragma mark - Groups v2

+ (TSRequest *)groupAuthenticationCredentialRequestWithFromRedemptionSeconds:(uint64_t)fromRedemptionSeconds
                                                         toRedemptionSeconds:(uint64_t)toRedemptionSeconds
    NS_SWIFT_NAME(groupAuthenticationCredentialRequest(fromRedemptionSeconds:toRedemptionSeconds:));

#pragma mark - Payments

+ (TSRequest *)paymentsAuthenticationCredentialRequest;

#pragma mark - Spam

+ (TSRequest *)pushChallengeRequest;
+ (TSRequest *)pushChallengeResponseWithToken:(NSString *)challengeToken;
+ (TSRequest *)recaptchChallengeResponseWithToken:(NSString *)serverToken captchaToken:(NSString *)captchaToken;

@end

NS_ASSUME_NONNULL_END
