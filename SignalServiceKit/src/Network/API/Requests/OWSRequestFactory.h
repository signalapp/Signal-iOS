//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/RemoteAttestation.h>

NS_ASSUME_NONNULL_BEGIN

@class ECKeyPair;
@class OWSDevice;
@class PreKeyRecord;
@class ProfileValue;
@class SMKUDAccessKey;
@class SignalServiceAddress;
@class SignedPreKeyRecord;
@class TSRequest;

typedef NS_ENUM(NSUInteger, TSVerificationTransport) { TSVerificationTransportVoice = 1, TSVerificationTransportSMS };

@interface OWSRequestFactory : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

+ (TSRequest *)enable2FARequestWithPin:(NSString *)pin;

+ (TSRequest *)disable2FARequest;

+ (TSRequest *)enableRegistrationLockV2RequestWithToken:(NSString *)token;

+ (TSRequest *)disableRegistrationLockV2Request;

+ (TSRequest *)acknowledgeMessageDeliveryRequestWithAddress:(SignalServiceAddress *)address timestamp:(UInt64)timestamp;

+ (TSRequest *)acknowledgeMessageDeliveryRequestWithServerGuid:(NSString *)serverGuid;

+ (TSRequest *)deleteDeviceRequestWithDevice:(OWSDevice *)device;

+ (TSRequest *)deviceProvisioningCodeRequest;

+ (TSRequest *)deviceProvisioningRequestWithMessageBody:(NSData *)messageBody ephemeralDeviceId:(NSString *)deviceId;

+ (TSRequest *)getDevicesRequest;

+ (TSRequest *)getMessagesRequest;

+ (TSRequest *)getUnversionedProfileRequestWithAddress:(SignalServiceAddress *)address
                                           udAccessKey:(nullable SMKUDAccessKey *)udAccessKey
    NS_SWIFT_NAME(getUnversionedProfileRequest(address:udAccessKey:));

+ (TSRequest *)getVersionedProfileRequestWithAddress:(SignalServiceAddress *)address
                                   profileKeyVersion:(nullable NSString *)profileKeyVersion
                                   credentialRequest:(nullable NSData *)credentialRequest
                                         udAccessKey:(nullable SMKUDAccessKey *)udAccessKey
    NS_SWIFT_NAME(getVersionedProfileRequest(address:profileKeyVersion:credentialRequest:udAccessKey:));

+ (TSRequest *)turnServerInfoRequest;

+ (TSRequest *)allocAttachmentRequestV2;

+ (TSRequest *)allocAttachmentRequestV3;

+ (TSRequest *)contactsIntersectionRequestWithHashesArray:(NSArray<NSString *> *)hashes;

+ (TSRequest *)profileAvatarUploadFormRequest;

+ (TSRequest *)registerForPushRequestWithPushIdentifier:(NSString *)identifier
                                         voipIdentifier:(nullable NSString *)voipId;

+ (TSRequest *)accountWhoAmIRequest;

+ (TSRequest *)unregisterAccountRequest;

+ (TSRequest *)requestPreauthChallengeRequestWithRecipientId:(NSString *)recipientId
                                                   pushToken:(NSString *)pushToken
                                                 isVoipToken:(BOOL)isVoipToken
    NS_SWIFT_NAME(requestPreauthChallengeRequest(recipientId:pushToken:isVoipToken:));

+ (TSRequest *)requestVerificationCodeRequestWithPhoneNumber:(NSString *)phoneNumber
                                            preauthChallenge:(nullable NSString *)preauthChallenge
                                                captchaToken:(nullable NSString *)captchaToken
                                                   transport:(TSVerificationTransport)transport;

+ (TSRequest *)submitMessageRequestWithAddress:(SignalServiceAddress *)recipientAddress
                                      messages:(NSArray *)messages
                                     timeStamp:(uint64_t)timeStamp
                                   udAccessKey:(nullable SMKUDAccessKey *)udAccessKey
                                      isOnline:(BOOL)isOnline;

+ (TSRequest *)submitMultiRecipientMessageRequestWithCiphertext:(NSData *)ciphertext
                                           compositeUDAccessKey:(SMKUDAccessKey *)udAccessKey
                                                      timestamp:(uint64_t)timestamp
                                                       isOnline:(BOOL)isOnline
    NS_SWIFT_NAME(submitMultiRecipientMessageRequest(ciphertext:compositeUDAccessKey:timestamp:isOnline:));

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

+ (TSRequest *)availablePreKeysCountRequest;

+ (TSRequest *)currentSignedPreKeyRequest;

+ (TSRequest *)recipientPreKeyRequestWithAddress:(SignalServiceAddress *)recipientAddress
                                        deviceId:(NSString *)deviceId
                                     udAccessKey:(nullable SMKUDAccessKey *)udAccessKey;

+ (TSRequest *)registerSignedPrekeyRequestWithSignedPreKeyRecord:(SignedPreKeyRecord *)signedPreKey;

+ (TSRequest *)registerPrekeysRequestWithPrekeyArray:(NSArray *)prekeys
                                         identityKey:(NSData *)identityKeyPublic
                                        signedPreKey:(SignedPreKeyRecord *)signedPreKey;

#pragma mark - Storage Service

+ (TSRequest *)storageAuthRequest;

#pragma mark - Remote Attestation

+ (TSRequest *)remoteAttestationAuthRequestForService:(RemoteAttestationService)service;

#pragma mark - CDS

+ (TSRequest *)cdsFeedbackRequestWithStatus:(NSString *)status
                                     reason:(nullable NSString *)reason NS_SWIFT_NAME(cdsFeedbackRequest(status:reason:));

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

#pragma mark - Usernames

+ (TSRequest *)usernameSetRequest:(NSString *)username;
+ (TSRequest *)usernameDeleteRequest;
+ (TSRequest *)getProfileRequestWithUsername:(NSString *)username;

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

+ (TSRequest *)groupAuthenticationCredentialRequestWithFromRedemptionDays:(uint32_t)fromRedemptionDays
                                                         toRedemptionDays:(uint32_t)toRedemptionDays
    NS_SWIFT_NAME(groupAuthenticationCredentialRequest(fromRedemptionDays:toRedemptionDays:));

#pragma mark - Payments

+ (TSRequest *)paymentsAuthenticationCredentialRequest;

#pragma mark - Subscriptions

+ (TSRequest *)subscriptionLevelsRequest;
+ (TSRequest *)setSubscriptionIDRequest:(NSString *)base64SubscriberID;
+ (TSRequest *)deleteSubscriptionIDRequest:(NSString *)base64SubscriberID;
+ (TSRequest *)subscriptionGetCurrentSubscriptionLevelRequest:(NSString *)base64SubscriberID;
+ (TSRequest *)subscriptionCreatePaymentMethodRequest:(NSString *)base64SubscriberID;
+ (TSRequest *)subscriptionSetDefaultPaymentMethodRequest:(NSString *)base64SubscriberID paymentID:(NSString *)paymentID;
+ (TSRequest *)subscriptionSetSubscriptionLevelRequest:(NSString *)base64SubscriberID level:(NSString *)level currency:(NSString *)currency idempotencyKey:(NSString *)idempotencyKey;
+ (TSRequest *)subscriptionRecieptCredentialsRequest:(NSString *)base64SubscriberID request:(NSString *)base64ReceiptCredentialRequest;
+ (TSRequest *)subscriptionRedeemRecieptCredential:(NSString *)base64ReceiptCredentialPresentation;
+ (TSRequest *)boostSuggestedAmountsRequest;
+ (TSRequest *)boostCreatePaymentIntentWithAmount:(NSUInteger)amount inCurrencyCode:(NSString *)currencyCode;
+ (TSRequest *)boostRecieptCredentialsWithPaymentIntentId:(NSString *)paymentIntentId
                                               andRequest:(NSString *)base64ReceiptCredentialRequest;
+ (TSRequest *)boostBadgesRequest;

#pragma mark - Spam

+ (TSRequest *)pushChallengeRequest;
+ (TSRequest *)pushChallengeResponseWithToken:(NSString *)challengeToken;
+ (TSRequest *)recaptchChallengeResponseWithToken:(NSString *)serverToken captchaToken:(NSString *)captchaToken;
+ (TSRequest *)reportSpamFromPhoneNumber:(NSString *)phoneNumber withServerGuid:(NSString *)serverGuid;

#pragma mark - Donations

+ (TSRequest *)createPaymentIntentWithAmount:(NSUInteger)amount
                              inCurrencyCode:(NSString *)currencyCode
                             withDescription:(nullable NSString *)description;

@end

NS_ASSUME_NONNULL_END
