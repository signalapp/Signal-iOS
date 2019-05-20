// Loki: Refer to Docs/SessionReset.md for explanations

#import "SessionCipher.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kNSNotificationName_SessionAdopted;
extern NSString *const kNSNotificationKey_ContactPubKey;

@interface SessionCipher (Loki)

/**
 Decrypt the given `CipherMessage`.
 This function is a wrapper around `throws_decrypt:protocolContext:` and adds on the custom Loki session handling.
 Refer to SignalServiceKit/Loki/Docs/SessionReset.md for an overview of how it works.

 @param whisperMessage The cipher message.
 @param protocolContext The protocol context (a `YapDatabaseReadWriteTransaction`).
 @return The decrypted data.
 */
- (NSData *)throws_lokiDecrypt:(id<CipherMessage>)whisperMessage protocolContext:(nullable id)protocolContext NS_SWIFT_UNAVAILABLE("throws Obj-C exceptions");

@end

NS_ASSUME_NONNULL_END
