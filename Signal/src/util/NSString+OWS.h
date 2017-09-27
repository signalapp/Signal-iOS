//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@interface NSString (OWS)

- (NSString *)ows_stripped;

- (NSString *)rtlSafeAppend:(NSString *)string referenceView:(UIView *)referenceView;

@end
