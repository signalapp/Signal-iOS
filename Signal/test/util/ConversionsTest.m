#import "ConversionsTest.h"
#import "Conversions.h"
#import "Util.h"
#import "TestUtil.h"

@implementation ConversionsTest

-(void) testDataWithBigEndianBytesOfUInt16 {
    test([[NSData dataWithBigEndianBytesOfUInt16:0x1234u] isEqualToData:[(@[@0x12, @0x34]) ows_toUint8Data]]);
}
-(void) testDataWithBigEndianBytesOfUInt32 {
    test([[NSData dataWithBigEndianBytesOfUInt32:0x12345678u] isEqualToData:[(@[@0x12, @0x34, @0x56, @0x78]) ows_toUint8Data]]);
}

-(void) testBigEndianUInt16At {
    NSData* d = [@[@0, @1, @2, @0xFF, @3, @4] ows_toUint8Data];
    test(0x1 == [d bigEndianUInt16At:0]);
    test(0x102 == [d bigEndianUInt16At:1]);
    test(0x2FF == [d bigEndianUInt16At:2]);
    test(0xFF03 == [d bigEndianUInt16At:3]);
    test(0x304 == [d bigEndianUInt16At:4]);
    testThrows([d bigEndianUInt16At:5]);
}
-(void) testBigEndianUInt32At {
    NSData* d = [@[@0, @1, @2, @0xFF, @3, @4] ows_toUint8Data];
    test(0x000102FFu == [d bigEndianUInt32At:0]);
    test(0x0102FF03u == [d bigEndianUInt32At:1]);
    test(0x02FF0304u == [d bigEndianUInt32At:2]);
    testThrows([d bigEndianUInt32At:3]);
}

@end
