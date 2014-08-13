#import "PhoneNumberDirectoryFilter.h"
#import "Environment.h"
#import "Constraints.h"
#import "PreferencesUtil.h"

#define HASH_COUNT_HEADER_KEY @"X-Hash-Count"
#define MIN_NEW_EXPIRATION_SECONDS (12 * 60 * 60)
#define MAX_EXPIRATION_SECONDS (24 * 60 * 60)

@implementation PhoneNumberDirectoryFilter

@synthesize bloomFilter;

+(PhoneNumberDirectoryFilter*) phoneNumberDirectoryFilterDefault {
    return [PhoneNumberDirectoryFilter phoneNumberDirectoryFilterWithBloomFilter:[BloomFilter bloomFilterWithNothing]
                                                               andExpirationDate:[NSDate date]];
}
+(PhoneNumberDirectoryFilter*) phoneNumberDirectoryFilterWithBloomFilter:(BloomFilter*)bloomFilter
                                                       andExpirationDate:(NSDate*)expirationDate {
    require(bloomFilter != nil);
    require(expirationDate != nil);
    PhoneNumberDirectoryFilter* newInstance = [PhoneNumberDirectoryFilter new];
    newInstance->bloomFilter = bloomFilter;
    newInstance->expirationDate = expirationDate;
    return newInstance;
}

-(NSDate*) getExpirationDate {
    NSDate* currentDate = [NSDate date];
    NSDate* maxExpiryDate = [NSDate dateWithTimeInterval:MAX_EXPIRATION_SECONDS sinceDate:currentDate];
    expirationDate = [expirationDate earlierDate:maxExpiryDate];
    return expirationDate;
}

+(PhoneNumberDirectoryFilter*) phoneNumberDirectoryFilterFromHttpResponse:(HttpResponse*)response {
    require(response != nil);
    
    checkOperation([response isOkResponse]);
    
    NSString* hashCountHeader = [response getHeaders][HASH_COUNT_HEADER_KEY];
    checkOperation(hashCountHeader != nil);
    
    int hashCountValue = [hashCountHeader intValue];
    checkOperation(hashCountValue > 0);
    
    NSData* responseBody = [response getOptionalBodyData];
    checkOperation([responseBody length] > 0);
    
    BloomFilter* bloomFilter = [BloomFilter bloomFilterWithHashCount:(NSUInteger)hashCountValue
                                                             andData:responseBody];
    
    NSTimeInterval expirationDuration = MIN_NEW_EXPIRATION_SECONDS
                                      + arc4random_uniform(MAX_EXPIRATION_SECONDS - MIN_NEW_EXPIRATION_SECONDS);
    NSDate* expirationDate = [NSDate dateWithTimeInterval:expirationDuration sinceDate:[NSDate date]];
    
    return [PhoneNumberDirectoryFilter phoneNumberDirectoryFilterWithBloomFilter:bloomFilter
                                                               andExpirationDate:expirationDate];
}

-(bool) containsPhoneNumber:(PhoneNumber*)phoneNumber {
    if (phoneNumber == nil) return false;
    return [bloomFilter contains:[phoneNumber toE164]];
}

@end
