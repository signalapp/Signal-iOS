//
//  PreKeyBundle+jsonDict.h
//  Signal
//
//  Created by Frederic Jacobs on 26/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "PreKeyBundle.h"

@interface PreKeyBundle (jsonDict)

+ (PreKeyBundle *)preKeyBundleFromDictionary:(NSDictionary *)dictionary forDeviceNumber:(NSNumber *)number;

@end
