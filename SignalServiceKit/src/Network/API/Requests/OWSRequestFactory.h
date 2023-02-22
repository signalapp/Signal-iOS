//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@class DeviceMessage;
@class ECKeyPair;
@class OWSDevice;
@class PreKeyRecord;
@class ProfileValue;
@class SMKUDAccessKey;
@class ServiceIdObjC;
@class SignalServiceAddress;
@class SignedPreKeyRecord;
@class TSRequest;

typedef NS_ENUM(NSUInteger, TSVerificationTransport) {
    TSVerificationTransportVoice = 1,
    TSVerificationTransportSMS
};

typedef NS_ENUM(uint8_t, OWSIdentity);

@interface OWSRequestFactory : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

+ (TSRequest *)disable2FARequest;

+ (TSRequest *)acknowledgeMessageDeliveryRequestWithServerGuid:(NSString *)serverGuid;

+ (TSRequest *)deleteDeviceRequestWithDevice:(OWSDevice *)device;

+ (TSRequest *)getDevicesRequest;

+ (TSRequest *)getMessagesRequest;

+ (TSRequest *)getUnversionedProfileRequestWithAddress:(SignalServiceAddress *)address
                                           udAccessKey:(nullable SMKUDAccessKey *)udAccessKey
    NS_SWIFT_NAME(getUnversionedProfileRequest(address:udAccessKey:));

+ (TSRequest *)getVersionedProfileRequestWithServiceId:(ServiceIdObjC *)serviceId
                                     profileKeyVersion:(nullable NSString *)profileKeyVersion
                                     credentialRequest:(nullable NSData *)credentialRequest
                                           udAccessKey:(nullable SMKUDAccessKey *)udAccessKey
    NS_SWIFT_NAME(getVersionedProfileRequest(serviceId:profileKeyVersion:credentialRequest:udAccessKey:));

+ (TSRequest *)turnServerInfoRequest;

+ (TSRequest *)allocAttachmentRequestV2;

+ (TSRequest *)allocAttachmentRequestV3;

+ (TSRequest *)contactsIntersectionRequestWithHashesArray:(NSArray<NSString *> *)hashes;

+ (TSRequest *)profileAvatarUploadFormRequest;

+ (TSRequest *)registerForPushRequestWithPushIdentifier:(NSString *)identifier
                                         voipIdentifier:(nullable NSString *)voipId;

+ (TSRequest *)accountWhoAmIRequest;

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

+ (TSRequest *)verifyPrimaryDeviceRequestWithVerificationCode:(NSString *)verificationCode
                                                  phoneNumber:(NSString *)phoneNumber
                                                      authKey:(NSString *)authKey
                                                          pin:(nullable NSString *)pin
                                    checkForAvailableTransfer:(BOOL)checkForAvailableTransfer
    NS_SWIFT_NAME(verifyPrimaryDeviceRequest(verificationCode:phoneNumber:authKey:pin:checkForAvailableTransfer:));

+ (TSRequest *)verifySecondaryDeviceRequestWithVerificationCode:(NSString *)verificationCode
                                                    phoneNumber:(NSString *)phoneNumber
                                                        authKey:(NSString *)authKey
                                            encryptedDeviceName:(NSData *)encryptedDeviceName
    NS_SWIFT_NAME(verifySecondaryDeviceRequest(verificationCode:phoneNumber:authKey:encryptedDeviceName:));

+ (TSRequest *)currencyConversionRequest NS_SWIFT_NAME(currencyConversionRequest());

#pragma mark - Attributes and Capabilities

+ (TSRequest *)updatePrimaryDeviceAttributesRequest;

+ (TSRequest *)updateSecondaryDeviceCapabilitiesRequest;

+ (NSDictionary<NSString *, NSNumber *> *)deviceCapabilitiesForLocalDevice;

#pragma mark - Prekeys

+ (TSRequest *)availablePreKeysCountRequestForIdentity:(OWSIdentity)identity;

+ (TSRequest *)currentSignedPreKeyRequest;

+ (TSRequest *)recipientPreKeyRequestWithServiceId:(ServiceIdObjC *)serviceId
                                          deviceId:(NSString *)deviceId
                                       udAccessKey:(nullable SMKUDAccessKey *)udAccessKey;

+ (TSRequest *)registerSignedPrekeyRequestForIdentity:(OWSIdentity)identity
                                         signedPreKey:(SignedPreKeyRecord *)signedPreKey;

+ (TSRequest *)registerPrekeysRequestForIdentity:(OWSIdentity)identity
                                     prekeyArray:(NSArray *)prekeys
                                     identityKey:(NSData *)identityKeyPublic
                                    signedPreKey:(SignedPreKeyRecord *)signedPreKey;

#pragma mark - Storage Service

+ (TSRequest *)storageAuthRequest;

#pragma mark - Remote Attestation

+ (TSRequest *)remoteAttestationAuthRequestForKeyBackup;
+ (TSRequest *)remoteAttestationAuthRequestForContactDiscovery;
+ (TSRequest *)remoteAttestationAuthRequestForCDSI;

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

+ (TSRequest *)versionedProfileSetRequestWithName:(nullable ProfileValue *)name
                                              bio:(nullable ProfileValue *)bio
                                         bioEmoji:(nullable ProfileValue *)bioEmoji
                                        hasAvatar:(BOOL)hasAvatar
                                   paymentAddress:(nullable ProfileValue *)paymentAddress
                                  visibleBadgeIds:(NSArray<NSString *> *)visibleBadgeIds
                                          version:(NSString *)version
                                       commitment:(NSData *)commitment;

#pragma mark - Remote Config

+ (TSRequest *)getRemoteConfigRequest;

#pragma mark - Groups v2

+ (TSRequest *)groupAuthenticationCredentialRequestWithFromRedemptionSeconds:(uint64_t)fromRedemptionSeconds
                                                         toRedemptionSeconds:(uint64_t)toRedemptionSeconds
    NS_SWIFT_NAME(groupAuthenticationCredentialRequest(fromRedemptionSeconds:toRedemptionSeconds:));

#pragma mark - Payments

+ (TSRequest *)paymentsAuthenticationCredentialRequest;

#pragma mark - Subscriptions

+ (TSRequest *)subscriptionGetCurrentSubscriptionLevelRequest:(NSString *)base64SubscriberID;
+ (TSRequest *)subscriptionCreateStripePaymentMethodRequest:(NSString *)base64SubscriberID;
+ (TSRequest *)subscriptionCreatePaypalPaymentMethodRequest:(NSString *)base64SubscriberID
                                                  returnUrl:(NSURL *)returnUrl
                                                  cancelUrl:(NSURL *)cancelUrl
    NS_SWIFT_NAME(subscriptionCreatePaypalPaymentMethodRequest(subscriberId:returnUrl:cancelUrl:));
+ (TSRequest *)subscriptionSetDefaultPaymentMethodRequest:(NSString *)base64SubscriberID
                                                processor:(NSString *)processor
                                                paymentID:(NSString *)paymentID;
+ (TSRequest *)subscriptionSetSubscriptionLevelRequest:(NSString *)base64SubscriberID level:(NSString *)level currency:(NSString *)currency idempotencyKey:(NSString *)idempotencyKey;
+ (TSRequest *)subscriptionReceiptCredentialsRequest:(NSString *)base64SubscriberID
                                             request:(NSString *)base64ReceiptCredentialRequest;
+ (TSRequest *)subscriptionRedeemReceiptCredential:(NSString *)base64ReceiptCredentialPresentation;
+ (TSRequest *)boostReceiptCredentialsWithPaymentIntentId:(NSString *)paymentIntentId
                                               andRequest:(NSString *)base64ReceiptCredentialRequest
                                      forPaymentProcessor:(NSString *)processor;

#pragma mark - Spam

+ (TSRequest *)pushChallengeRequest;
+ (TSRequest *)pushChallengeResponseWithToken:(NSString *)challengeToken;
+ (TSRequest *)recaptchChallengeResponseWithToken:(NSString *)serverToken captchaToken:(NSString *)captchaToken;

@end

NS_ASSUME_NONNULL_END
