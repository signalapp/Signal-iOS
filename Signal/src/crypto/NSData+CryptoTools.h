#import <Foundation/Foundation.h>

@interface NSData (CryptoTools)

- (NSData*)hashWithSHA256;

- (NSData*)hmacWithSHA1WithKey:(NSData*)key;
- (NSData*)hmacWithSHA256WithKey:(NSData*)key;

- (NSData*)encryptWithAESInCipherFeedbackModeWithKey:(NSData*)key andIV:(NSData*)iv;
- (NSData*)decryptWithAESInCipherFeedbackModeWithKey:(NSData*)key andIV:(NSData*)iv;

- (NSData*)encryptWithAESInCipherBlockChainingModeWithPkcs7PaddingWithKey:(NSData*)key andIV:(NSData*)iv;
- (NSData*)decryptWithAESInCipherBlockChainingModeWithPkcs7PaddingWithKey:(NSData*)key andIV:(NSData*)iv;

- (NSData*)encryptWithAESInCounterModeWithKey:(NSData*)key andIV:(NSData*)iv;
- (NSData*)decryptWithAESInCounterModeWithKey:(NSData*)key andIV:(NSData*)iv;

/// Determines if two data vectors contain the same information.
/// Avoids short-circuiting or data-dependent branches, so that early returns can't be used to infer where the difference is.
/// Returns early if data is of different length.
- (bool)isEqualToData_TimingSafe:(NSData*)other;

@end
