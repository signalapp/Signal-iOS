//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@class ECKeyPair;
@class RKCK;

@interface RootKey : NSObject <NSSecureCoding>

- (instancetype)initWithData:(NSData *)data;
- (RKCK *)throws_createChainWithTheirEphemeral:(NSData *)theirEphemeral
                                  ourEphemeral:(ECKeyPair *)ourEphemeral NS_SWIFT_UNAVAILABLE("throws objc exceptions");

@property (nonatomic, readonly) NSData *keyData;

@end
