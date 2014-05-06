#import "BloomFilterTest.h"
#import "BloomFilter.h"
#import "TestUtil.h"

@implementation BloomFilterTest

-(void) testEmptyBloomFilter {
    NSMutableData* d = [NSMutableData dataWithLength:100];
    BloomFilter* b = [BloomFilter bloomFilterWithHashCount:5 andData:d];
    NSArray* keys = @[@"", @"a", @"wonder", @"b"];
    for (NSString* key in keys) {
        test(![b contains:key]);
    }
}
-(void) testFullBloomFilter {
    NSMutableData* d = [NSMutableData dataWithLength:100];
    for (NSUInteger i = 0; i < 100; i++) {
        [d setUint8At:i to:0xFF];
    }
    BloomFilter* b = [BloomFilter bloomFilterWithHashCount:5 andData:d];
    NSArray* keys = @[@"", @"a", @"wonder", @"b"];
    for (NSString* key in keys) {
        test([b contains:key]);
    }
}

@end
