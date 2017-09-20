//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@interface TSRequest : NSMutableURLRequest

@property (nonatomic, retain) NSMutableDictionary *parameters;

- (void)makeAuthenticatedRequest;

@end
