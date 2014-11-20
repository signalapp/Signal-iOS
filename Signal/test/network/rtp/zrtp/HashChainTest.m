#import <XCTest/XCTest.h>
#import "HashChain.h"
#import "Util.h"
#import "CryptoTools.h"
#import "TestUtil.h"

@interface HashChainTest : XCTestCase

@end

@implementation HashChainTest
-(void) testHashChainKnown {
    testThrows([HashChain hashChainWithSeed:nil]);
    NSData* d0 = [NSMutableData dataWithLength:32];
    NSData* d1 = [@[@0x66,@0x68,@0x7A,@0xAD,@0xF8,@0x62,@0xBD,@0x77,@0x6C,@0x8F,@0xC1,@0x8B,@0x8E,@0x9F,@0x8E,@0x20,@0x08,@0x97,@0x14,@0x85,@0x6E,@0xE2,@0x33,@0xB3,@0x90,@0x2A,@0x59,@0x1D,@0x0D,@0x5F,@0x29,@0x25] ows_toUint8Data];
    NSData* d2 = [d1 hashWithSha256];
    NSData* d3 = [d2 hashWithSha256];
    
    HashChain* h = [HashChain hashChainWithSeed:d0];
    test([[h h0] isEqualToData:d0]);
    test([[h h1] isEqualToData:d1]);
    test([[h h2] isEqualToData:d2]);
    test([[h h3] isEqualToData:d3]);
}
-(void) testHashChainRandom {
    HashChain* h = [HashChain hashChainWithSecureGeneratedData];
    
    // maybe we'll find a collision! ... maybe not
    test(![[h h1] isEqualToData:[h h3]]);
    test(![[[HashChain hashChainWithSecureGeneratedData] h2] isEqualToData:[[HashChain hashChainWithSecureGeneratedData] h2]]);
}
@end
