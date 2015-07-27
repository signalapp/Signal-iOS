#import <XCTest/XCTest.h>
#import "MasterSecret.h"
#import "TestUtil.h"

@interface MasterSecretTest : XCTestCase

@end

@implementation MasterSecretTest
-(void) testKnownCalculateSharedSecret {
    NSData* dhResult = [NSMutableData dataWithLength:384];
    NSData* totalHash = [NSMutableData dataWithLength:32];
    Zid* initiatorZid = [Zid zidWithData:[NSMutableData dataWithLength:12]];
    Zid* responderZid = [Zid zidWithData:[NSMutableData dataWithLength:12]];
    NSData* sharedSecret = [MasterSecret calculateSharedSecretFromDhResult:dhResult
                                                              andTotalHash:totalHash
                                                           andInitiatorZid:initiatorZid
                                                           andResponderZid:responderZid];
    // the expected data here was obtained from the android redphone implementation
    NSData* expectedSharedSecret = [(@[@54,@78,@99,@226,@49,@17,@8,@135,@65,@33,@247,@134,@235,@29,@164,@217,@18,@44,@241,@18,@172,@63,@197,@178,@71,@42,@253,@150,@238,@173,@218,@131]) ows_toUint8Data];
    test([sharedSecret isEqualToData:expectedSharedSecret]);
}
-(void) testKnownMasterSecret {
    NSData* sharedSecret = [NSMutableData dataWithLength:32];
    NSData* totalHash = [NSMutableData dataWithLength:32];
    Zid* initiatorZid = [Zid zidWithData:[NSMutableData dataWithLength:12]];
    Zid* responderZid = [Zid zidWithData:[NSMutableData dataWithLength:12]];
    
    // the expected data here was obtained from the android redphone implementation
    MasterSecret* m = [MasterSecret masterSecretFromSharedSecret:sharedSecret andTotalHash:totalHash andInitiatorZid:initiatorZid andResponderZid:responderZid];
    test([[m shortAuthenticationStringData] isEqualToData:[(@[@241,@140,@246,@102]) ows_toUint8Data]]);
    test([[m initiatorSrtpKey] isEqualToData:[(@[@202,@139,@183,@119,@244,@164,@247,@11,@232,@161,@199,@120,@229,@49,@239,@141]) ows_toUint8Data]]);
    test([[m responderSrtpKey] isEqualToData:[(@[@35,@126,@130,@159,@156,@218,@64,@6,@59,@170,@139,@77,@250,@103,@84,@152]) ows_toUint8Data]]);
    test([[m initiatorSrtpSalt] isEqualToData:[(@[@92,@22,@129,@225,@169,@155,@6,@157,@34,@49,@76,@15,@196,@180]) ows_toUint8Data]]);
    test([[m responderSrtpSalt] isEqualToData:[(@[@151,@124,@181,@201,@203,@218,@192,@141,@244,@247,@249,@144,@213,@133]) ows_toUint8Data]]);
    test([[m initiatorMacKey] isEqualToData:[(@[@215,@167,@226,@196,@14,@124,@137,@75,@48,@110,@159,@47,@243,@238,@171,@213,@103,@181,@70,@206]) ows_toUint8Data]]);
    test([[m responderMacKey] isEqualToData:[(@[@215,@225,@180,@37,@18,@248,@122,@2,@24,@12,@149,@241,@8,@193,@103,@102,@117,@50,@27,@138]) ows_toUint8Data]]);
    test([[m initiatorZrtpKey] isEqualToData:[(@[@182,@239,@29,@23,@42,@7,@231,@48,@45,@244,@177,@84,@77,@62,@56,@48]) ows_toUint8Data]]);
    test([[m responderZrtpKey] isEqualToData:[(@[@59,@57,@33,@50,@121,@161,@218,@19,@255,@246,@98,@228,@68,@142,@50,@175]) ows_toUint8Data]]);
}
@end
