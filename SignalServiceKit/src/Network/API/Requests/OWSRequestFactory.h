//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ECKeyPair;
@class OWSDevice;
@class PreKeyRecord;
@class SignedPreKeyRecord;
@class TSRequest;

typedef NS_ENUM(NSUInteger, TSVerificationTransport) { TSVerificationTransportVoice = 1, TSVerificationTransportSMS };

@interface OWSRequestFactory : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (TSRequest *)enable2FARequestWithPin:(NSString *)pin;

+ (TSRequest *)disable2FARequest;

+ (TSRequest *)acknowledgeMessageDeliveryRequestWithSource:(NSString *)source timestamp:(UInt64)timestamp;

+ (TSRequest *)deleteDeviceRequestWithDevice:(OWSDevice *)device;

+ (TSRequest *)deviceProvisioningCodeRequest;

+ (TSRequest *)deviceProvisioningRequestWithMessageBody:(NSData *)messageBody ephemeralDeviceId:(NSString *)deviceId;

+ (TSRequest *)getDevicesRequest;

+ (TSRequest *)getMessagesRequest;

+ (TSRequest *)getProfileRequestWithRecipientId:(NSString *)recipientId;

+ (TSRequest *)turnServerInfoRequest;

+ (TSRequest *)allocAttachmentRequest;

+ (TSRequest *)attachmentRequestWithAttachmentId:(UInt64)attachmentId;

+ (TSRequest *)availablePreKeysCountRequest;

+ (TSRequest *)contactsIntersectionRequestWithHashesArray:(NSArray<NSString *> *)hashes;

+ (TSRequest *)currentSignedPreKeyRequest;

+ (TSRequest *)profileAvatarUploadFormRequest;

+ (TSRequest *)recipientPrekeyRequestWithRecipient:(NSString *)recipientNumber deviceId:(NSString *)deviceId;

+ (TSRequest *)registerForPushRequestWithPushIdentifier:(NSString *)identifier voipIdentifier:(NSString *)voipId;

+ (TSRequest *)updateAttributesRequestWithManualMessageFetching:(BOOL)enableManualMessageFetching;

+ (TSRequest *)unregisterAccountRequest;

+ (TSRequest *)requestVerificationCodeRequestWithPhoneNumber:(NSString *)phoneNumber
                                                   transport:(TSVerificationTransport)transport;

+ (TSRequest *)submitMessageRequestWithRecipient:(NSString *)recipientId
                                        messages:(NSArray *)messages
                                       timeStamp:(uint64_t)timeStamp;

+ (TSRequest *)registerSignedPrekeyRequestWithSignedPreKeyRecord:(SignedPreKeyRecord *)signedPreKey;

+ (TSRequest *)registerPrekeysRequestWithPrekeyArray:(NSArray *)prekeys
                                         identityKey:(NSData *)identityKeyPublic
                                        signedPreKey:(SignedPreKeyRecord *)signedPreKey;

+ (TSRequest *)remoteAttestationRequest:(ECKeyPair *)keyPair
                              enclaveId:(NSString *)enclaveId
                           authUsername:(NSString *)authUsername
                           authPassword:(NSString *)authPassword;

+ (TSRequest *)enclaveContactDiscoveryRequestWithId:(NSData *)requestId
                                       addressCount:(NSUInteger)addressCount
                               encryptedAddressData:(NSData *)encryptedAddressData
                                            cryptIv:(NSData *)cryptIv
                                           cryptMac:(NSData *)cryptMac
                                          enclaveId:(NSString *)enclaveId
                                       authUsername:(NSString *)authUsername
                                       authPassword:(NSString *)authPassword
                                            cookies:(NSArray<NSHTTPCookie *> *)cookies;

+ (TSRequest *)remoteAttestationAuthRequest;
+ (TSRequest *)cdsFeedbackRequestWithResult:(NSString *)result NS_SWIFT_NAME(cdsFeedbackRequest(result:));

@end

NS_ASSUME_NONNULL_END
