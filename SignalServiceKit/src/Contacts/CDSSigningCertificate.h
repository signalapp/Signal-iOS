//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface CDSSigningCertificate : NSObject

+ (nullable CDSSigningCertificate *)parseCertificateFromPem:(NSString *)certificatePem;

//- (BOOL)isDebugQuote;

- (BOOL)verifySignatureOfBody:(NSString *)body signature:(NSData *)theirSignature;

@end

NS_ASSUME_NONNULL_END
