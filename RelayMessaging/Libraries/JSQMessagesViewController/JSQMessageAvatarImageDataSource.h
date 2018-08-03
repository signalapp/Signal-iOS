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

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

/**
 *  The `JSQMessageAvatarImageDataSource` protocol defines the common interface through which
 *  a `JSQMessagesViewController` and `JSQMessagesCollectionView` interact with avatar image model objects.
 *
 *  It declares the required and optional methods that a class must implement so that instances
 *  of that class can be display properly within a `JSQMessagesCollectionViewCell`.
 *
 *  A concrete class that conforms to this protocol is provided in the library. See `JSQMessagesAvatarImage`.
 *
 *  @see JSQMessagesAvatarImage.
 */
@protocol JSQMessageAvatarImageDataSource <NSObject>

@required

/**
 *  @return The avatar image for a regular display state.
 *  
 *  @discussion You may return `nil` from this method while the image is being downloaded.
 */
- (UIImage *)avatarImage;

/**
 *  @return The avatar image for a highlighted display state. 
 *  
 *  @discussion You may return `nil` from this method if this does not apply.
 */
- (UIImage *)avatarHighlightedImage;

/**
 *  @return A placeholder avatar image to be displayed if avatarImage is not yet available, or `nil`.
 *  For example, if avatarImage needs to be downloaded, this placeholder image
 *  will be used until avatarImage is not `nil`.
 *
 *  @discussion If you do not need support for a placeholder image, that is, your images 
 *  are stored locally on the device, then you may simply return the same value as avatarImage here.
 *
 *  @warning You must not return `nil` from this method.
 */
- (UIImage *)avatarPlaceholderImage;

@end
