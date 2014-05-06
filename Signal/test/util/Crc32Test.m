#import "Crc32Test.h"
#import "Crc32.h"
#import "TestUtil.h"

@implementation Crc32Test
-(void) testKnownCrc32 {
    char* valText = "The quick brown fox jumps over the lazy dog";
    NSData* val = [NSMutableData dataWithBytes:valText length:strlen(valText)];
    test(0x414fa339 == [val crc32]);
}

@end
