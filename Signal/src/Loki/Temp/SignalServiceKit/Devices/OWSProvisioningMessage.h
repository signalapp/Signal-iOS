//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface OWSProvisioningMessage : NSObject

- (instancetype)initWithMyPublicKey:(NSData *)myPublicKey
                       myPrivateKey:(NSData *)myPrivateKey
                     theirPublicKey:(NSData *)theirPublicKey
                  accountIdentifier:(NSString *)accountIdentifier
                         profileKey:(NSData *)profileKey
                readReceiptsEnabled:(BOOL)areReadReceiptsEnabled
                   provisioningCode:(NSString *)provisioningCode;

- (nullable NSData *)buildEncryptedMessageBody;

@end

NS_ASSUME_NONNULL_END
