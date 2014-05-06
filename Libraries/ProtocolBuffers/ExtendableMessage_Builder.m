// Copyright 2008 Cyrus Najmabadi
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import "ExtendableMessage_Builder.h"

#import "ExtendableMessage.h"
#import "ExtensionField.h"
#import "WireFormat.h"
#import "ExtensionRegistry.h"

@implementation PBExtendableMessage_Builder

- (PBExtendableMessage*) internalGetResult {
  @throw [NSException exceptionWithName:@"ImproperSubclassing" reason:@"" userInfo:nil];
}


/**
 * Called by subclasses to parse an unknown field or an extension.
 * @return {@code YES} unless the tag is an end-group tag.
 */
- (BOOL) parseUnknownField:(PBCodedInputStream*) input
             unknownFields:(PBUnknownFieldSet_Builder*) unknownFields
         extensionRegistry:(PBExtensionRegistry*) extensionRegistry
                       tag:(int32_t) tag {
  PBExtendableMessage* message = [self internalGetResult];
  int32_t wireType = PBWireFormatGetTagWireType(tag);
  int32_t fieldNumber = PBWireFormatGetTagFieldNumber(tag);

  id<PBExtensionField> extension = [extensionRegistry getExtension:[message class]
                                                       fieldNumber:fieldNumber];

  if (extension != nil) {
    if ([extension wireType] == wireType) {
      [extension mergeFromCodedInputStream:input
                             unknownFields:unknownFields
                         extensionRegistry:extensionRegistry
                                   builder:self
                                       tag:tag];
      return YES;
    }
  }

  return [super parseUnknownField:input unknownFields:unknownFields extensionRegistry:extensionRegistry tag:tag];
}


- (id) getExtension:(id<PBExtensionField>) extension {
  return [[self internalGetResult] getExtension:extension];
}


- (BOOL) hasExtension:(id<PBExtensionField>) extension {
  return [[self internalGetResult] hasExtension:extension];
}


- (PBExtendableMessage_Builder*) setExtension:(id<PBExtensionField>) extension
                                        value:(id) value {
  PBExtendableMessage* message = [self internalGetResult];
  [message ensureExtensionIsRegistered:extension];

  if ([extension isRepeated]) {
    @throw [NSException exceptionWithName:@"IllegalArgument" reason:@"Must call addExtension() for repeated types." userInfo:nil];
  }

  if (message.extensionMap == nil) {
    message.extensionMap = [NSMutableDictionary dictionary];
  }
  [message.extensionMap setObject:value forKey:[NSNumber numberWithInt:[extension fieldNumber]]];
  return self;
}


- (PBExtendableMessage_Builder*) addExtension:(id<PBExtensionField>) extension
                                        value:(id) value {
  PBExtendableMessage* message = [self internalGetResult];
  [message ensureExtensionIsRegistered:extension];

  if (![extension isRepeated]) {
    @throw [NSException exceptionWithName:@"IllegalArgument" reason:@"Must call setExtension() for singular types." userInfo:nil];
  }

  if (message.extensionMap == nil) {
    message.extensionMap = [NSMutableDictionary dictionary];
  }
  NSNumber* fieldNumber = [NSNumber numberWithInt:[extension fieldNumber]];
  NSMutableArray* list = [message.extensionMap objectForKey:fieldNumber];
  if (list == nil) {
    list = [NSMutableArray array];
    [message.extensionMap setObject:list forKey:fieldNumber];
  }

  [list addObject:value];
  return self;
}


- (PBExtendableMessage_Builder*) setExtension:(id<PBExtensionField>) extension
                                        index:(int32_t) index
                                        value:(id) value {
  PBExtendableMessage* message = [self internalGetResult];
  [message ensureExtensionIsRegistered:extension];

  if (![extension isRepeated]) {
    @throw [NSException exceptionWithName:@"IllegalArgument" reason:@"Must call setExtension() for singular types." userInfo:nil];
  }

  if (message.extensionMap == nil) {
    message.extensionMap = [NSMutableDictionary dictionary];
  }

  NSNumber* fieldNumber = [NSNumber numberWithInt:[extension fieldNumber]];
  NSMutableArray* list = [message.extensionMap objectForKey:fieldNumber];

  [list replaceObjectAtIndex:(NSUInteger)index withObject:value];

  return self;
}


- (PBExtendableMessage_Builder*) clearExtension:(id<PBExtensionField>) extension {
  PBExtendableMessage* message = [self internalGetResult];
  [message ensureExtensionIsRegistered:extension];
  [message.extensionMap removeObjectForKey:[NSNumber numberWithInt:[extension fieldNumber]]];

  return self;
}


- (void) mergeExtensionFields:(PBExtendableMessage*) other {
  PBExtendableMessage* thisMessage = [self internalGetResult];
  if ([thisMessage class] != [other class]) {
    @throw [NSException exceptionWithName:@"IllegalArgument" reason:@"Cannot merge extensions from a different type" userInfo:nil];
  }

  if (other.extensionMap.count > 0) {
    if (thisMessage.extensionMap == nil) {
      thisMessage.extensionMap = [NSMutableDictionary dictionary];
    }

    NSDictionary* registry = other.extensionRegistry;
    for (NSNumber* fieldNumber in other.extensionMap) {
      id<PBExtensionField> thisField = [registry objectForKey:fieldNumber];
      id value = [other.extensionMap objectForKey:fieldNumber];

      if ([thisField isRepeated]) {
        NSMutableArray* list = [thisMessage.extensionMap objectForKey:fieldNumber];
        if (list == nil) {
          list = [NSMutableArray array];
          [thisMessage.extensionMap setObject:list forKey:fieldNumber];
        }

        [list addObjectsFromArray:value];
      } else {
        [thisMessage.extensionMap setObject:value forKey:fieldNumber];
      }
    }
  }
}

@end
