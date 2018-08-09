//
//  ForstaColors.h
//  Forsta
//
//  Created by Mark on 9/21/17.
//  Copyright © 2017 Forsta. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ForstaColors : UIColor

+(UIColor *)randomPopColor;

+(NSArray <UIColor *>*)popColors;
+(NSDictionary *)outgoingBubbleColors;
+(NSDictionary *)incomingBubbleColors;

+(UIColor *)lightGray;
+(UIColor *)mediumGray;
+(UIColor *)darkGray;
+(UIColor *)darkestGray;

+(UIColor *)darkGreen;
+(UIColor *)mediumDarkGreen;
+(UIColor *)mediumGreen;
+(UIColor *)mediumLightGreen;
+(UIColor *)lightGreen;

+(UIColor *)darkRed;
+(UIColor *)mediumDarkRed;
+(UIColor *)mediumRed;
+(UIColor *)mediumLightRed;
+(UIColor *)lightRed;

+(UIColor *)darkBlue1;
+(UIColor *)mediumDarkBlue1;
+(UIColor *)mediumBlue1;
+(UIColor *)mediumLightBlue1;
+(UIColor *)lightBlue1;

+(UIColor *)darkBlue2;
+(UIColor *)mediumDarkBlue2;
+(UIColor *)mediumBlue2;
+(UIColor *)mediumLightBlue2;
+(UIColor *)lightBlue2;

+(UIColor *)lightPurple;
+(UIColor *)mediumPurple;

+(UIColor *)lightYellow;
+(UIColor *)mediumYellow;

+(UIColor *)lightPink;
+(UIColor *)mediumPink;
@end
