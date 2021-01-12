//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "AVAudioSession+OWS.h"

@implementation AVAudioSession(OWS)


- (BOOL)ows_setCategory:(AVAudioSessionCategory)category withOptions:(AVAudioSessionCategoryOptions)options error:(NSError **)outError API_AVAILABLE(ios(6.0), watchos(2.0), tvos(9.0)) API_UNAVAILABLE(macos)
{
    return [self setCategory:category withOptions:options error:outError];
}

@end
