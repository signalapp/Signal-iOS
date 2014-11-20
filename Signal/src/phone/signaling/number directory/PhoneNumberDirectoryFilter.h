#import <Foundation/Foundation.h>
#import "BloomFilter.h"
#import "PhoneNumber.h"

/**
 *
 * PhoneNumberDirectoryFilter matches numbers-to-be-called against a bloom filter that determines if those numbers are red phone compatible.
 * The bloom filter expires periodically, and must be updated from the whispersystem servers.
 *
 */
@interface PhoneNumberDirectoryFilter : NSObject

@property (strong, nonatomic, readonly, getter=getExpirationDate) NSDate* expirationDate;
@property (nonatomic, readonly) BloomFilter* bloomFilter;

+ (instancetype)defaultFilter;

- (instancetype)initWithBloomFilter:(BloomFilter*)bloomFilter andExpirationDate:(NSDate*)expirationDate;
- (instancetype)initFromURLResponse:(NSHTTPURLResponse*)response body:(NSData*)data;

- (bool)containsPhoneNumber:(PhoneNumber*)phoneNumber;

@end
