//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@interface OWSProvisioningMessage : NSObject

- (instancetype)initWithMyPublicKey:(NSData *)myPublicKey
                       myPrivateKey:(NSData *)myPrivateKey
                     theirPublicKey:(NSData *)theirPublicKey
                  accountIdentifier:(NSString *)accountIdentifier
                   provisioningCode:(NSString *)provisioningCode;

- (NSData *)buildEncryptedMessageBody;

@end

NS_ASSUME_NONNULL_END
