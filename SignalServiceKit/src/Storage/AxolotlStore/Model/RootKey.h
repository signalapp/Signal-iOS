//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface RootKey : NSObject <NSSecureCoding>

- (instancetype)initWithData:(NSData *)data;

@property (nonatomic, readonly) NSData *keyData;

@end
