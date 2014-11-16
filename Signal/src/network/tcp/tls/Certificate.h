#import <Foundation/Foundation.h>

/**
 *
 * Certificate is responsible for loading, exposing, and managing a SecCertificateRef.
 *
 */
@interface Certificate : NSObject

// This is unused, do we still need it?
- (instancetype)initFromTrust:(SecTrustRef)trust
                      atIndex:(CFIndex)index;

- (instancetype)initFromResourcePath:(NSString*)resourcePath
                              ofType:(NSString*)resourceType;

- (void)setAsAnchorForTrust:(SecTrustRef)trust;

@end
