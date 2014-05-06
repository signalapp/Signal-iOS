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

#import "WireFormat.h"
@class PBCodedInputStream;
@class PBUnknownFieldSet_Builder;
@class PBExtendableMessage_Builder;
@class PBCodedOutputStream;
@class PBExtensionRegistry;

@protocol PBExtensionField
- (int32_t) fieldNumber;
- (PBWireFormat) wireType;
- (BOOL) isRepeated;
- (Class) extendedClass;
- (id) defaultValue;

- (void) mergeFromCodedInputStream:(PBCodedInputStream*) input
                     unknownFields:(PBUnknownFieldSet_Builder*) unknownFields
                 extensionRegistry:(PBExtensionRegistry*) extensionRegistry
                           builder:(PBExtendableMessage_Builder*) builder
                               tag:(int32_t) tag;
- (void) writeValue:(id) value includingTagToCodedOutputStream:(PBCodedOutputStream*) output;
- (int32_t) computeSerializedSizeIncludingTag:(id) value;
@end
