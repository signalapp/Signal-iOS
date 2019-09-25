//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SignalServiceAddress;

@interface OWSProvisioningMessage : NSObject

- (instancetype)initWithMyPublicKey:(NSData *)myPublicKey
                       myPrivateKey:(NSData *)myPrivateKey
                     theirPublicKey:(NSData *)theirPublicKey
                     accountAddress:(SignalServiceAddress *)accountAddress
                         profileKey:(NSData *)profileKey
                readReceiptsEnabled:(BOOL)areReadReceiptsEnabled
                   provisioningCode:(NSString *)provisioningCode;

- (nullable NSData *)buildEncryptedMessageBody;

@end

NS_ASSUME_NONNULL_END
