//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "Chain.h"
#import "RootKey.h"
#import "SessionState.h"
#import <Foundation/Foundation.h>

@class ECKeyPair;

@interface RKCK : NSObject

@property (nonatomic,strong) RootKey  *rootKey;
@property (nonatomic,strong) ChainKey *chainKey;

-(instancetype) initWithRK:(RootKey*)rootKey CK:(ChainKey*)chainKey;

@end
