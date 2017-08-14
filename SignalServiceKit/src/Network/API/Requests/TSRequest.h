//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface TSRequest : NSMutableURLRequest

@property (nonatomic, retain) NSMutableDictionary *parameters;

- (void)makeAuthenticatedRequest;

#pragma mark - Factory methods

// move to builder class/header
+ (instancetype)setProfileNameRequestWithProfileName:(NSString *)encryptedName;

@end
