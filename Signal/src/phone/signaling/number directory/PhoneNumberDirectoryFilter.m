#import "PhoneNumberDirectoryFilter.h"
#import "Environment.h"
#import "Constraints.h"
#import "PropertyListPreferences+Util.h"

#define HASH_COUNT_HEADER_KEY @"X-Hash-Count"
#define MIN_NEW_EXPIRATION_SECONDS (12 * 60 * 60)
#define MAX_EXPIRATION_SECONDS (24 * 60 * 60)

@interface PhoneNumberDirectoryFilter ()

@property (strong, nonatomic, readwrite, getter=getExpirationDate) NSDate* expirationDate;
@property (nonatomic, readwrite) BloomFilter* bloomFilter;

@end

@implementation PhoneNumberDirectoryFilter

+ (instancetype)defaultFilter {
    return [[self alloc] initWithBloomFilter:[BloomFilter bloomFilterWithNothing] andExpirationDate:[NSDate date]];
}

- (instancetype)initWithBloomFilter:(BloomFilter*)bloomFilter andExpirationDate:(NSDate*)expirationDate {
    if (self = [super init]) {
        require(bloomFilter != nil);
        require(expirationDate != nil);
        
        self.bloomFilter = bloomFilter;
        self.expirationDate = expirationDate;
    }
    
    return self;
}

- (instancetype)initFromURLResponse:(NSHTTPURLResponse*)response body:(NSData*)data {
    require(response != nil);
    
    checkOperation(response.statusCode == 200);
    
    NSString* hashCountHeader = response.allHeaderFields[HASH_COUNT_HEADER_KEY];
    checkOperation(hashCountHeader != nil);
    
    int hashCountValue = hashCountHeader.intValue;
    checkOperation(hashCountValue > 0);
    
    NSData* responseBody = data;
    checkOperation(responseBody.length > 0);
    
    BloomFilter* bloomFilter = [[BloomFilter alloc] initWithHashCount:(NSUInteger)hashCountValue
                                                              andData:responseBody];
    
    NSTimeInterval expirationDuration = MIN_NEW_EXPIRATION_SECONDS
                                      + arc4random_uniform(MAX_EXPIRATION_SECONDS - MIN_NEW_EXPIRATION_SECONDS);
    NSDate* expirationDate = [NSDate dateWithTimeInterval:expirationDuration sinceDate:[NSDate date]];
    
    return [self initWithBloomFilter:bloomFilter andExpirationDate:expirationDate];
}

- (NSDate*)getExpirationDate {
    NSDate* currentDate = [NSDate date];
    NSDate* maxExpiryDate = [NSDate dateWithTimeInterval:MAX_EXPIRATION_SECONDS sinceDate:currentDate];
    _expirationDate = [_expirationDate earlierDate:maxExpiryDate];
    return _expirationDate;
}

- (bool)containsPhoneNumber:(PhoneNumber*)phoneNumber {
    if (phoneNumber == nil) return false;
    return [self.bloomFilter contains:phoneNumber.toE164];
}

@end
