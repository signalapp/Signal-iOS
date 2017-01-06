//
//  AppVersion.h
//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@interface AppVersion : NSObject

@property (nonatomic, readonly) NSString *firstAppVersion;
@property (nonatomic, readonly) NSString *lastAppVersion;
@property (nonatomic, readonly) NSString *currentAppVersion;

+ (instancetype)instance;

@end
