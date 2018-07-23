//
//  Created by Jesse Squires
//  http://www.jessesquires.com
//
//
//  Documentation
//  http://cocoadocs.org/docsets/JSQMessagesViewController
//
//
//  GitHub
//  https://github.com/jessesquires/JSQMessagesViewController
//
//
//  License
//  Copyright (c) 2014 Jesse Squires
//  Released under an MIT license: http://opensource.org/licenses/MIT
//

#import <UIKit/UIKit.h>

@interface UIColor (JSQMessages)

#pragma mark - Message bubble colors

/**
 *  @return A color object containing HSB values similar to the iOS 7 messages app green bubble color.
 */
+ (UIColor *)jsq_messageBubbleGreenColor;

/**
 *  @return A color object containing HSB values similar to the iOS 7 messages app blue bubble color.
 */
+ (UIColor *)jsq_messageBubbleBlueColor;

/**
 *  @return A color object containing HSB values similar to the iOS 7 red color.
 */
+ (UIColor *)jsq_messageBubbleRedColor;

/**
 *  @return A color object containing HSB values similar to the iOS 7 messages app light gray bubble color.
 */
+ (UIColor *)jsq_messageBubbleLightGrayColor;

#pragma mark - Utilities

/**
 *  Creates and returns a new color object whose brightness component is decreased by the given value, using the initial color values of the receiver.
 *
 *  @param value A floating point value describing the amount by which to decrease the brightness of the receiver.
 *
 *  @return A new color object whose brightness is decreased by the given values. The other color values remain the same as the receiver.
 */
- (UIColor *)jsq_colorByDarkeningColorWithValue:(CGFloat)value;

@end