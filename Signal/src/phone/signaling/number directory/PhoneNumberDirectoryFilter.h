#import <Foundation/Foundation.h>
#import "BloomFilter.h"
#import "PhoneNumber.h"

/**
 *
 * PhoneNumberDirectoryFilter matches numbers-to-be-called against a bloom filter that determines if those numbers are red phone compatible.
 * The bloom filter expires periodically, and must be updated from the whispersystem servers.
 *
 */
@interface PhoneNumberDirectoryFilter : NSObject {
@private NSDate* expirationDate;
}

@property (nonatomic,readonly) BloomFilter* bloomFilter;

+(PhoneNumberDirectoryFilter*) phoneNumberDirectoryFilterDefault;
+(PhoneNumberDirectoryFilter*) phoneNumberDirectoryFilterWithBloomFilter:(BloomFilter*)bloomFilter
                                                       andExpirationDate:(NSDate*)expirationDate;
+(PhoneNumberDirectoryFilter*) phoneNumberDirectoryFilterFromURLResponse:(NSHTTPURLResponse*)response body:(NSData*)data;

-(bool) containsPhoneNumber:(PhoneNumber*)phoneNumber;
-(NSDate*) getExpirationDate;

@end
