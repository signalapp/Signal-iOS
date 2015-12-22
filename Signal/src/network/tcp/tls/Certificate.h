#import <Foundation/Foundation.h>

/**
 *
 * Certificate is responsible for loading, exposing, and managing a SecCertificateRef.
 *
 */

@interface Certificate : NSObject

+ (Certificate *)certificateFromTrust:(SecTrustRef)trust atIndex:(CFIndex)index;

+ (Certificate *)certificateFromResourcePath:(NSString *)resourcePath ofType:(NSString *)resourceType;

- (void)setAsAnchorForTrust:(SecTrustRef)trust;

@end
