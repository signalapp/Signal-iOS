//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "Cryptography.h"
#import "NSData+messagePadding.h"
#import "SSKBaseTest.h"

@interface MessagePaddingTests : SSKBaseTest

@end

@implementation MessagePaddingTests

- (void)testV3Padding {
    for (NSUInteger i=0;i<159;i++) {
        NSData *data = [NSMutableData dataWithLength:i];
        XCTAssert([data paddedMessageBody].length == 159);
    }
    
    for (NSUInteger i=159;i<319;i++) {
        NSData *data = [NSMutableData dataWithLength:i];
        XCTAssert([data paddedMessageBody].length == 319);
    }
    
    for (NSUInteger i=319;i<479;i++) {
        NSData *data = [NSMutableData dataWithLength:i];
        XCTAssert([data paddedMessageBody].length == 479);
    }
}

- (void)testV3RandomPadding{
    for (int i = 0; i < 1000; i++) {
        NSData *randomMessage = [Cryptography generateRandomBytes:501];
        NSData *paddedMessage = [randomMessage paddedMessageBody];
        XCTAssert([[paddedMessage removePadding] isEqualToData:randomMessage]);
    }
}

@end
