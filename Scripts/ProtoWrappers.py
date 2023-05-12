#!/usr/bin/env python3

import os
import sys
import subprocess
import datetime
import argparse
import re


git_repo_path = os.path.abspath(
    subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()
)

enum_item_regex = re.compile(r'^(.+?)\s*=\s*(\d+?)\s*;$')
enum_regex = re.compile(r'^enum\s+(.+?)\s+\{$')
message_item_regex = re.compile(r'^(optional|required|repeated)?\s*([\w\d\.]+?\s)\s*([\w\d]+?)\s*=\s*(\d+?)\s*(\[default = (.+)\])?;$')
message_regex = re.compile(r'^message\s+(.+?)\s+\{$')
multiline_comment_regex = re.compile(r'/\*.*?\*/', re.MULTILINE|re.DOTALL)
oneof_item_regex = re.compile(r'^(.+?)\s*([\w\d]+?)\s*=\s*(\d+?)\s*;$')
oneof_regex = re.compile(r'^oneof\s+(.+?)\s+\{$')
option_regex = re.compile(r'^option ')
package_regex = re.compile(r'^package\s+(.+);')
reserved_regex = re.compile(r'^reserved\s+(?:/*[^*]*\*/)?\s*\d+;$')
syntax_regex = re.compile(r'^syntax\s+=\s+"(.+)";')
validation_start_regex = re.compile(r'// MARK: - Begin Validation Logic for ([^ ]+) -')

skip_signal_service_address_types = [
    "StorageServiceProtoContactRecord",
    "SSKProtoContactDetails",
    "SSKProtoBodyRange",
    "SSKProtoDataMessageQuote",
    "SSKProtoVerified",
    "SSKProtoSyncMessageSentUnidentifiedDeliveryStatus",
    "SSKProtoSyncMessageRead",
    "SSKProtoSyncMessageViewed",
    "SSKProtoSyncMessageViewOnceOpen",
    "SSKProtoSyncMessageMessageRequestResponse",
    "SSKProtoDataMessageReaction",
    "SSKProtoSyncMessageOutgoingPayment",
    "SSKProtoDataMessageStoryContext",
    "SSKProtoSyncMessageSentStoryMessageRecipient",
]

proto_syntax = None

def lower_camel_case(name):
    result = name

    # We have at least two segments, we'll have to split them up
    if '_' in name:
        splits = name.split('_')
        splits = [captialize_first_letter(split.lower()) for split in splits]
        splits[0] = splits[0].lower()
        result = ''.join(splits)

    # This name is all caps, lowercase it
    elif name.isupper():
        result = name.lower()

    return supress_adjacent_capital_letters(result)

def camel_case(name):
    result = name

    splits = name.split('_')
    splits = [captialize_first_letter(split) for split in splits]
    result = ''.join(splits)

    return supress_adjacent_capital_letters(result)

def captialize_first_letter(name):
    if name.isupper():
        name = name.lower()
    
    return name[0].upper() + name[1:]

# The generated code for "Apple Swift Protos" suppresses
# adjacent capital letters in lower_camel_case.
def supress_adjacent_capital_letters(name):
    chars = []
    lastWasUpper = False
    for char in name:
        if lastWasUpper:
            char = char.lower()
        chars.append(char)
        lastWasUpper = char.isupper()
    result = ''.join(chars)
    if result.endswith('Id'):
        result = result[:-2] + 'ID'
    if result.endswith('Url'):
        result = result[:-3] + 'URL'
    return result


def swift_type_for_proto_primitive_type(proto_type):
    if proto_type == 'string':
        return 'String'
    elif proto_type == 'uint64':
        return 'UInt64'
    elif proto_type == 'uint32':
        return 'UInt32'
    elif proto_type == 'fixed64':
        return 'UInt64'
    elif proto_type == 'int64':
        return 'Int64'
    elif proto_type == 'int32':
        return 'Int32'
    elif proto_type == 'bool':
        return 'Bool'
    elif proto_type == 'bytes':
        return 'Data'
    elif proto_type == 'double':
        return 'Double'
    elif proto_type == 'float':
        return 'Float'
    else:
        return None

def is_swift_primitive_type(proto_type):
    return proto_type in ('String', 'UInt64', 'UInt32', 'Int64', 'Int32', 'Bool', 'Data', 'Double', 'Float')

# Provides context for writing an indented block surrounded by braces.
#
# e.g.
#
#     with BracedContext('class Foo', writer) as writer:
#         with BracedContext('func bar() -> Bool', writer) as writer:
#             return true
#
# Produces:
#
#    class Foo {
#        func bar() -> Bool {
#            return true
#        }
#    }
#
class BracedContext:
    def __init__(self, line, writer):
        self.writer = writer
        writer.add('%s {' % line)

    def __enter__(self):
        self.writer.push_indent()
        return self.writer

    def __exit__(self, *args):
        self.writer.pop_indent()
        self.writer.add('}')

class WriterContext:
    def __init__(self, proto_name, swift_name, parent=None):
        self.proto_name = proto_name
        self.swift_name = swift_name
        self.parent = parent
        self.name_map = {}

class LineWriter:
    def __init__(self, args):
        self.contexts = []
        # self.indent = 0
        self.lines = []
        self.args = args
        self.current_indent = 0

    def braced(self, line):
        return BracedContext(line, self)

    def push_indent(self):
        self.current_indent = self.current_indent + 1

    def pop_indent(self):
        self.current_indent = self.current_indent - 1
        if self.current_indent < 0:
            raise Exception('Invalid indentation')

    def all_context_proto_names(self):
        return [context.proto_name for context in self.contexts]

    def current_context(self):
        return self.contexts[-1]

    def indent(self):
        return self.current_indent
        # return len(self.contexts)

    def push_context(self, proto_name, swift_name):
        self.contexts.append(WriterContext(proto_name, swift_name))
        self.push_indent()

    def pop_context(self):
        self.contexts.pop()
        self.pop_indent()

    def add(self, line):
        self.lines.append(('    ' * self.indent()) + line)

    def add_raw(self, line):
        self.lines.append(line)

    def extend(self, text):
        for line in text.split('\n'):
            self.add(line)

    def join(self):
        lines = [line.rstrip() for line in self.lines]
        return '\n'.join(lines)

    def rstrip(self):
        lines = self.lines
        while len(lines) > 0 and len(lines[-1].strip()) == 0:
            lines = lines[:-1]
        self.lines = lines

    def newline(self):
        self.add('')

    def needs_objc(self):
        return proto_syntax == 'proto2';

    def add_objc(self):
        if self.needs_objc():
            self.add('@objc ')


class BaseContext(object):
    def __init__(self):
        self.parent = None
        self.proto_name = None

    def inherited_proto_names(self):
        if self.parent is None:
            return []
        if self.proto_name is None:
            return []
        return self.parent.inherited_proto_names() + [self.proto_name,]

    def derive_swift_name(self):
        names = self.inherited_proto_names()
        return self.args.wrapper_prefix + ''.join(names)

    def derive_wrapped_swift_name(self):
        names = self.inherited_proto_names()
        return self.args.proto_prefix + '_' + '.'.join(names)

    def qualified_proto_name(self):
        names = self.inherited_proto_names()
        return '.'.join(names)

    def children(self):
        return []

    def descendents(self):
        result = []
        for child in self.children():
            result.append(child)
            result.extend(child.descendents())
        return result

    def siblings(self):
        result = []
        if self.parent is not None:
            result = self.parent.children()
        return result

    def ancestors(self):
        result = []
        if self.parent is not None:
            result.append(self.parent)
            result.extend(self.parent.ancestors())
        return result

    def context_for_proto_type(self, field):
        should_deep_search = '.' in field.proto_type
        for candidate in self.all_known_contexts(should_deep_search=should_deep_search):
            if candidate.proto_name == field.proto_type:
                return candidate
            if candidate.qualified_proto_name() == field.proto_type:
                return candidate
            if candidate.derive_swift_name() == field.proto_type:
                return candidate

        return None

    def all_known_contexts(self,should_deep_search=False):
        if should_deep_search:
            root_ancestor = self.ancestors()[-1]
            return root_ancestor.descendents()

        candidates = []
        candidates.extend(self.descendents())
        candidates.extend(self.siblings())
        for ancestor in self.ancestors():
            if ancestor.proto_name is None:
                # Ignore the root context
                continue
            candidates.append(ancestor)
            candidates.extend(ancestor.siblings())
        return candidates


    def base_swift_type_for_field(self, field):
        swift_type = swift_type_for_proto_primitive_type(field.proto_type)
        if swift_type is not None:
            return swift_type
        else:
            matching_context = self.context_for_proto_type(field)
            if matching_context is not None:
                return matching_context.swift_name
            else:
                # Failure
                return field.proto_type

    def swift_type_for_field(self, field, suppress_optional=False):
        base_type = self.base_swift_type_for_field(field)
        
        if field.rules == 'optional':
            if suppress_optional:
                return base_type
            can_be_optional = self.can_field_be_optional(field)
            if can_be_optional:
                return '%s?' % base_type
            else:
                return base_type
        elif field.rules == 'required':
            return base_type
        elif field.rules == 'repeated':
            return '[%s]' % base_type
        else:
            raise Exception('Unknown field type')

    def is_field_primitive(self, field):
        return field.proto_type in ('uint64',
            'uint32',
            'fixed64',
            'bool', 
            'double', )

    def can_field_be_optional(self, field):
        if self.is_field_primitive(field):
            return not field.is_required

        # if field.proto_type == 'uint64':
        #     return False
        # elif field.proto_type == 'uint32':
        #     return False
        # elif field.proto_type == 'fixed64':
        #     return False
        # elif field.proto_type == 'bool':
        #     return False
        # elif self.is_field_an_enum(field):
        if self.is_field_an_enum(field):
            return True
        else:
            return True

    def is_field_an_enum(self, field):
        matching_context = self.context_for_proto_type(field)
        if matching_context is not None:
            if type(matching_context) is EnumContext:
                return True
        return False

    def is_field_oneof(self, field):
        matching_context = self.context_for_proto_type(field)
        if matching_context is not None:
            if type(matching_context) is OneOfContext:
                return True
        return False

    def is_field_a_proto(self, field):
        matching_context = self.context_for_proto_type(field)
        if matching_context is not None:
            if type(matching_context) is MessageContext:
                return True
        return False

    def is_field_a_proto_whose_init_throws(self, field):
        matching_context = self.context_for_proto_type(field)
        if matching_context is not None:
            if type(matching_context) is MessageContext:
                return matching_context.can_init_throw()
        return False

    def can_field_be_optional_objc(self, field):
        return self.can_field_be_optional(field) and not self.is_field_primitive(field) and not self.is_field_an_enum(field)

    def default_value_for_field(self, field):
        if field.rules == 'repeated':
            return '[]'

        if field.default_value is not None and len(field.default_value) > 0:
            return field.default_value

        if field.rules == 'optional':
            can_be_optional = self.can_field_be_optional(field)
            if can_be_optional:
                return None # Swift provides this automatically.

        if field.proto_type == 'uint64':
            return '0'
        elif field.proto_type == 'uint32':
            return '0'
        elif field.proto_type == 'fixed64':
            return '0'
        elif field.proto_type == 'double':
            return '0'
        elif field.proto_type == 'bool':
            return 'false'
        elif self.is_field_an_enum(field):
            # TODO: Assert that rules is empty.
            enum_context = self.context_for_proto_type(field)
            return enum_context.default_value()

        return None


class FileContext(BaseContext):
    def __init__(self, args):
        BaseContext.__init__(self)

        self.args = args

        self.messages = []
        self.enums = []

    def children(self):
        return self.enums + self.messages

    def prepare(self):
        for child in self.children():
            child.prepare()

    def generate(self, writer):
        writer.extend('''//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import SwiftProtobuf''')

        writer.newline()
        writer.extend('''
// WARNING: This code is generated. Only edit within the markers.
'''.strip())
        writer.newline()

        writer.invalid_protobuf_error_name = '%sError' % self.args.wrapper_prefix
        writer.extend(('''
public enum %s: Error {
    case invalidProtobuf(description: String)
}
''' % writer.invalid_protobuf_error_name).strip())
        writer.newline()

        for child in self.children():
            child.generate(writer)


class MessageField:
    def __init__(self, name, index, rules, proto_type, default_value, sort_index, is_required):
        self.name = name
        self.index = index
        self.rules = rules
        self.proto_type = proto_type
        self.default_value = default_value
        self.sort_index = sort_index
        self.is_required = is_required

    def has_accessor_name(self):
        name = 'has' + self.name_swift[0].upper() + self.name_swift[1:]
        if name == 'hasId':
            # TODO: I'm not sure why "Apple Swift Proto" code formats the
            # the name in this way.
            name = 'hasID'
        elif name == 'hasUrl':
            # TODO: I'm not sure why "Apple Swift Proto" code formats the
            # the name in this way.
            name = 'hasURL'
        return name

class MessageContext(BaseContext):
    def __init__(self, args, parent, proto_name):
        BaseContext.__init__(self)

        self.args = args
        self.parent = parent

        self.proto_name = proto_name

        self.messages = []
        self.enums = []
        self.oneofs = []

        self.field_map = {}

    def fields(self):
        fields = self.field_map.values()
        fields = sorted(fields, key=lambda f: f.sort_index)
        return fields

    def field_indices(self):
        return [field.index for field in self.fields()]

    def field_names(self):
        return [field.name for field in self.fields()]

    def children(self):
        return self.enums + self.messages + self.oneofs

    def can_init_throw(self):
        for field in self.fields():
            if self.is_field_a_proto_whose_init_throws(field):
                return True
            if field.is_required and proto_syntax == "proto2":
                return True
        return False

    def prepare(self):
        self.swift_name = self.derive_swift_name()
        self.swift_builder_name = "%sBuilder" % self.swift_name

        for child in self.children():
            child.prepare()

    def generate(self, writer):
        for child in self.messages:
            child.generate(writer)

        for child in self.enums:
            child.generate(writer)

        for child in self.oneofs:
            child.generate(writer)

        writer.add('// MARK: - %s' % self.swift_name)
        writer.newline()

        if writer.needs_objc():
            writer.add_objc()
            writer.add('public class %s: NSObject, Codable, NSSecureCoding {' % self.swift_name)
        else:
            writer.add('public struct %s: Codable, CustomDebugStringConvertible {' % self.swift_name)
        writer.newline()

        writer.push_context(self.proto_name, self.swift_name)

        wrapped_swift_name = self.derive_wrapped_swift_name()

        # Prepare fields
        explict_fields = []
        implict_fields = []
        uuid_field = None
        e164_field = None
        for field in self.fields():
            field.type_swift = self.swift_type_for_field(field)
            field.type_swift_not_optional = self.swift_type_for_field(field, suppress_optional=True)
            field.name_swift = lower_camel_case(field.name)

            is_explicit = False
            if field.is_required:
                is_explicit = True
            elif self.is_field_a_proto(field):
                is_explicit = True
            if is_explicit:
                explict_fields.append(field)
            else:
                implict_fields.append(field)

            # See if we need to add SignalServiceAddress helpers
            if self.swift_name in skip_signal_service_address_types:
                pass
            elif field.name.endswith('Uuid') and field.proto_type == 'string':
                uuid_field = field
            elif field.name.endswith('E164') and field.proto_type == 'string':
                e164_field = field

            # Ensure that no enum are required.
            if proto_syntax == 'proto2' and self.is_field_an_enum(field) and field.is_required:
                raise Exception('Enum fields cannot be required: %s.%s' % ( self.proto_name, field.name, ))

        writer.add('fileprivate let proto: %s' % wrapped_swift_name )
        writer.newline()

        # Property Declarations
        if len(explict_fields) > 0:
            for field in explict_fields:
                type_name = field.type_swift_not_optional if field.is_required else field.type_swift
                writer.add_objc()
                writer.add('public let %s: %s' % (field.name_swift, type_name))

                if (not field.is_required) and field.rules != 'repeated' and (not self.is_field_a_proto(field)):
                    writer.add_objc()
                    writer.add('public var %s: Bool {' % field.has_accessor_name() )
                    writer.push_indent()
                    writer.add('return proto.%s' % field.has_accessor_name() )
                    writer.pop_indent()
                    writer.add('}')
                writer.newline()

        if len(implict_fields) > 0:
            for field in implict_fields:
                if field.rules == 'optional':
                    can_be_optional = not self.is_field_primitive(field)
                    if can_be_optional:
                        def write_field_getter(is_objc_accessible, is_required_optional):
                            
                            if is_required_optional:
                                writer.add('// This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.')
                                if is_objc_accessible:
                                    writer.add_objc()
                                writer.add('public var unwrapped%s: %s {' % ( camel_case(field.name_swift), field.type_swift_not_optional, ))
                                writer.push_indent()
                                writer.add('if !%s {' % field.has_accessor_name() )
                                writer.push_indent()
                                writer.add('// TODO: We could make this a crashing assert.')
                                writer.add('owsFailDebug("Unsafe unwrap of missing optional: %s.%s.")' % ( self.proto_name, field.name_swift, ) )
                                writer.pop_indent()
                                writer.add('}')
                            else:
                                if is_objc_accessible:
                                    writer.add_objc()
                                writer.add('public var %s: %s? {' % ( field.name_swift, field.type_swift_not_optional, ))
                                writer.push_indent()
                                writer.add('guard %s else {' % field.has_accessor_name() )
                                writer.push_indent()
                                writer.add('return nil')
                                writer.pop_indent()
                                writer.add('}')
                            if self.is_field_an_enum(field):
                                enum_context = self.context_for_proto_type(field)
                                writer.add('return %s(proto.%s)' % ( enum_context.wrap_func_name(), field.name_swift, ) )
                            elif self.is_field_oneof(field):
                                oneof_context = self.context_for_proto_type(field)
                                writer.add('guard let %s = proto.%s else {' % ( field.name_swift, field.name_swift, ))
                                writer.push_indent()
                                writer.add('owsFailDebug("%s was unexpectedly nil")' % field.name_swift )
                                writer.add('return nil')
                                writer.pop_indent()
                                writer.add('}')
                                writer.add('guard let unwrapped%s = try? %s(%s) else {' % ( camel_case(field.name_swift), oneof_context.wrap_func_name(), field.name_swift, ))
                                writer.push_indent()
                                writer.add('owsFailDebug("failed to unwrap %s")' % field.name_swift )
                                writer.add('return nil')
                                writer.pop_indent()
                                writer.add('}')
                                writer.add('return unwrapped%s' % camel_case(field.name_swift) )
                            else:
                                writer.add('return proto.%s' % field.name_swift )
                            writer.pop_indent()
                            writer.add('}')
                        if self.is_field_an_enum(field):
                            write_field_getter(is_objc_accessible=False, is_required_optional=False)
                            write_field_getter(is_objc_accessible=True, is_required_optional=True)
                        elif self.is_field_oneof(field):
                            write_field_getter(is_objc_accessible=False, is_required_optional=False)
                        else:
                            write_field_getter(is_objc_accessible=True, is_required_optional=False)
                    else:
                        writer.add_objc()
                        writer.add('public var %s: %s {' % (field.name_swift, field.type_swift_not_optional))
                        writer.push_indent()
                        if self.is_field_an_enum(field):
                            enum_context = self.context_for_proto_type(field)
                            writer.add('return %s(proto.%s)' % ( enum_context.wrap_func_name(), field.name_swift, ) )
                        else:
                            writer.add('return proto.%s' % field.name_swift )
                        writer.pop_indent()
                        writer.add('}')

                    writer.add_objc()
                    writer.add('public var %s: Bool {' % field.has_accessor_name() )
                    writer.push_indent()
                    if proto_syntax == 'proto3':
                        # TODO: We might want to return false for unknown/0 enum?                        
                        if field.proto_type in ['bytes', 'string']:
                            writer.add('return !proto.%s.isEmpty' % field.name_swift )
                        else:
                            writer.add('return true')
                    else:
                        is_uuid_or_e164 = field.name.endswith('Uuid') or field.name.endswith('E164')
                        if is_uuid_or_e164:
                            writer.add('return proto.%s && !proto.%s.isEmpty' % ( field.has_accessor_name(), field.name_swift, ) ) 
                        else:
                            writer.add('return proto.%s' % field.has_accessor_name() ) 
                    writer.pop_indent()
                    writer.add('}')
                    writer.newline()
                elif field.rules == 'repeated':
                    writer.add_objc()
                    writer.add('public var %s: %s {' % (field.name_swift, field.type_swift_not_optional))
                    writer.push_indent()
                    writer.add('return proto.%s' % field.name_swift )
                    writer.pop_indent()
                    writer.add('}')
                    writer.newline()
                else:
                    writer.add_objc()
                    writer.add('public var %s: %s {' % (field.name_swift, field.type_swift_not_optional))
                    writer.push_indent()
                    if self.is_field_an_enum(field):
                        enum_context = self.context_for_proto_type(field)
                        writer.add('return %s(proto.%s)' % ( enum_context.unwrap_func_name(), field.name_swift, ) )
                    elif self.is_field_oneof(field):
                        oneof_context = self.context_for_proto_type(field)
                        writer.add('return %s(proto.%s)' % ( oneof_context.unwrap_func_name(), field.name_swift, ) )
                    else:
                        writer.add('return proto.%s' % field.name_swift )
                    writer.pop_indent()
                    writer.add('}')
                    writer.newline()

        address_accessor = ''
        if uuid_field is not None:
            accessor_prefix = uuid_field.name.replace('Uuid', '')
            address_accessor = accessor_prefix + 'Address'
            address_has_accessor = 'hasValid' + accessor_prefix[0].upper() + accessor_prefix[1:]

            # hasValidAddress
            writer.add_objc()
            writer.add('public var %s: Bool {' % address_has_accessor)
            writer.push_indent()
            writer.add('return %s != nil' % address_accessor)
            writer.pop_indent()
            writer.add('}')

            # address accessor
            writer.add_objc()
            writer.add('public let %s: SignalServiceAddress?' % address_accessor)
            writer.newline()

        # Unknown fields
        writer.add('public var hasUnknownFields: Bool {')
        writer.push_indent()
        writer.add('return !proto.unknownFields.data.isEmpty')
        writer.pop_indent()
        writer.add('}')

        writer.add('public var unknownFields: SwiftProtobuf.UnknownStorage? {')
        writer.push_indent()
        writer.add('guard hasUnknownFields else { return nil }')
        writer.add('return proto.unknownFields')
        writer.pop_indent()
        writer.add('}')
        writer.newline()

        # Initializer
        initializer_parameters = []
        initializer_parameters.append('proto: %s' % wrapped_swift_name)
        initializer_prefix = 'private init('
        for field in explict_fields:
            type_name = field.type_swift_not_optional if field.is_required else field.type_swift
            parameter = '%s: %s' % (field.name_swift, type_name)
            parameter = '\n' + ' ' * len(initializer_prefix) + parameter
            initializer_parameters.append(parameter)
        initializer_parameters = ', '.join(initializer_parameters)
        writer.extend('%s%s) {' % ( initializer_prefix, initializer_parameters, ) )
        writer.push_indent()
        writer.add('self.proto = proto')
        for field in explict_fields:
            writer.add('self.%s = %s' % (field.name_swift, field.name_swift))

        if uuid_field:
            writer.newline()

            if proto_syntax == 'proto3':
                writer.add('let %s = !proto.%s.isEmpty' % (uuid_field.has_accessor_name(), uuid_field.name_swift))
                if e164_field:
                    writer.add('let %s = !proto.%s.isEmpty' % (e164_field.has_accessor_name(), e164_field.name_swift))
            else:
                writer.add('let %s = proto.%s && !proto.%s.isEmpty' % (uuid_field.has_accessor_name(), uuid_field.has_accessor_name(), uuid_field.name_swift))
                if e164_field:
                    writer.add('let %s = proto.%s && !proto.%s.isEmpty' % (e164_field.has_accessor_name(), e164_field.has_accessor_name(), e164_field.name_swift))

            writer.add('let %s: String? = proto.%s' % (uuid_field.name_swift, uuid_field.name_swift))
            if e164_field:
                writer.add('let %s: String? = proto.%s' % (e164_field.name_swift, e164_field.name_swift))

            writer.add('self.%s = {' % address_accessor)
            writer.push_indent()

            if e164_field:
                writer.add(f"guard {uuid_field.has_accessor_name()} || {e164_field.has_accessor_name()} else {{ return nil }}")
            else:
                writer.add(f"guard {uuid_field.has_accessor_name()} else {{ return nil }}")
            writer.newline()

            writer.add('let uuidString: String? = {')
            writer.push_indent()
            writer.add('guard %s else { return nil }' % uuid_field.has_accessor_name())
            writer.newline()
            writer.add('guard let %s = %s else {' % (uuid_field.name_swift, uuid_field.name_swift))
            writer.push_indent()
            writer.add('owsFailDebug("%s was unexpectedly nil")' % uuid_field.name_swift)
            writer.add('return nil')
            writer.pop_indent()
            writer.add('}')
            writer.newline()
            writer.add('return %s' % uuid_field.name_swift)
            writer.pop_indent()
            writer.add('}()')
            writer.newline()

            if e164_field:
                writer.add('let phoneNumber: String? = {')
                writer.push_indent()
                writer.add('guard %s else {' % e164_field.has_accessor_name())
                writer.push_indent()
                writer.add('return nil')
                writer.pop_indent()
                writer.add('}')
                writer.newline()
                writer.add('return ProtoUtils.parseProtoE164(%s, name: "%s.%s")' % (e164_field.name_swift, wrapped_swift_name, e164_field.name_swift))
                writer.pop_indent()
                writer.add('}()')
                writer.newline()

                writer.add("let address = SignalServiceAddress(")
                writer.push_indent()
                writer.add("uuidString: uuidString,")
                writer.add("phoneNumber: phoneNumber")
                writer.pop_indent()
                writer.add(")")
            else:
                writer.add("guard let uuidString = uuidString else { return nil }")
                writer.newline()

                writer.add("let address = SignalServiceAddress(uuidString: uuidString)")

            writer.add("guard address.isValid else {")
            writer.push_indent()
            writer.add('owsFailDebug("address was unexpectedly invalid")')
            writer.add("return nil")
            writer.pop_indent()
            writer.add("}")
            writer.newline()
            writer.add('return address')
            writer.pop_indent()
            writer.add('}()')

        writer.pop_indent()
        writer.add('}')
        writer.newline()

        # serializedData() func
        writer.add_objc()
        writer.extend(('''
public func serializedData() throws -> Data {
    return try self.proto.serializedData()
}
''').strip())
        writer.newline()

        # init(serializedData:) func
        if writer.needs_objc():
            writer.add_objc()
            writer.add('public convenience init(serializedData: Data) throws {')
        else:
            writer.add('public init(serializedData: Data) throws {')
        writer.push_indent()
        writer.add('let proto = try %s(serializedData: serializedData)' % ( wrapped_swift_name, ) )
        if self.can_init_throw():
            writer.add('try self.init(proto)')
        else:
            writer.add('self.init(proto)')
        writer.pop_indent()
        writer.add('}')
        writer.newline()

        # init(proto:) func
        chunks = ["fileprivate"]
        if writer.needs_objc():
            chunks.append("convenience")
        chunks.append(f"init(_ proto: {wrapped_swift_name})")
        if self.can_init_throw():
            chunks.append("throws")
        chunks.append("{")
        writer.add(" ".join(chunks))
        writer.push_indent()

        for field in explict_fields:
            if field.is_required:

                if proto_syntax == 'proto2':
                    writer.add('guard proto.%s else {' % field.has_accessor_name() )
                    writer.push_indent()
                    writer.add('throw %s.invalidProtobuf(description: "\(Self.logTag()) missing required field: %s")' % ( writer.invalid_protobuf_error_name, field.name_swift, ) )
                    writer.pop_indent()
                    writer.add('}')

                if self.is_field_an_enum(field):
                    # TODO: Assert that rules is empty.
                    enum_context = self.context_for_proto_type(field)
                    writer.add('let %s = %s(proto.%s)' % ( field.name_swift, enum_context.wrap_func_name(), field.name_swift, ) )
                elif self.is_field_a_proto_whose_init_throws(field):
                    writer.add('let %s = try %s(proto.%s)' % (field.name_swift, self.base_swift_type_for_field(field), field.name_swift)),
                elif self.is_field_a_proto(field):
                    writer.add('let %s = %s(proto.%s)' % (field.name_swift, self.base_swift_type_for_field(field), field.name_swift)),
                else:
                    writer.add('let %s = proto.%s' % ( field.name_swift, field.name_swift, ) )
                writer.newline()
                continue

            default_value = self.default_value_for_field(field)
            if default_value is None:
                writer.add('var %s: %s' % (field.name_swift, field.type_swift))
            else:
                writer.add('var %s: %s = %s' % (field.name_swift, field.type_swift, default_value))

            if field.rules == 'repeated':
                if self.is_field_an_enum(field):
                    enum_context = self.context_for_proto_type(field)
                    writer.add('%s = proto.%s.map { %s($0) }' % ( field.name_swift, field.name_swift, enum_context.wrap_func_name(), ) )
                elif self.is_field_a_proto_whose_init_throws(field):
                    writer.add('%s = try proto.%s.map { try %s($0) }' % ( field.name_swift, field.name_swift, self.base_swift_type_for_field(field), ) )
                elif self.is_field_a_proto(field):
                    writer.add('%s = proto.%s.map { %s($0) }' % ( field.name_swift, field.name_swift, self.base_swift_type_for_field(field), ) )
                else:
                    writer.add('%s = proto.%s' % ( field.name_swift, field.name_swift, ) )
            else:
                writer.add('if proto.%s {' % field.has_accessor_name() )
                writer.push_indent()

                if self.is_field_an_enum(field):
                    # TODO: Assert that rules is empty.
                    enum_context = self.context_for_proto_type(field)
                    writer.add('%s = %s(proto.%s)' % ( field.name_swift, enum_context.wrap_func_name(), field.name_swift, ) )
                elif self.is_field_a_proto_whose_init_throws(field):
                    writer.add('%s = try %s(proto.%s)' % (field.name_swift, self.base_swift_type_for_field(field), field.name_swift)),
                elif self.is_field_a_proto(field):
                    writer.add('%s = %s(proto.%s)' % (field.name_swift, self.base_swift_type_for_field(field), field.name_swift)),
                else:
                    writer.add('%s = proto.%s' % ( field.name_swift, field.name_swift, ) )

                writer.pop_indent()
                writer.add('}')
            writer.newline()

        initializer_prefix = 'self.init('
        initializer_arguments = []
        initializer_arguments.append('proto: proto')
        for field in explict_fields:
            argument = '%s: %s' % (field.name_swift, field.name_swift)
            argument = '\n' + ' ' * len(initializer_prefix) + argument
            initializer_arguments.append(argument)
        initializer_arguments = ', '.join(initializer_arguments)
        writer.extend('%s%s)' % ( initializer_prefix, initializer_arguments, ) )
        writer.pop_indent()
        writer.add('}')
        writer.newline()

        # codable

        if writer.needs_objc():
            writer.add('public required convenience init(from decoder: Swift.Decoder) throws {')
        else:
            writer.add('public init(from decoder: Swift.Decoder) throws {')
        writer.push_indent()
        writer.add('let singleValueContainer = try decoder.singleValueContainer()')
        writer.add('let serializedData = try singleValueContainer.decode(Data.self)')
        writer.add('try self.init(serializedData: serializedData)')
        writer.pop_indent()
        writer.add('}')

        writer.add('public func encode(to encoder: Swift.Encoder) throws {')
        writer.push_indent()
        writer.add('var singleValueContainer = encoder.singleValueContainer()')
        writer.add('try singleValueContainer.encode(try serializedData())')
        writer.pop_indent()
        writer.add('}')
        writer.newline()

        # NSSecureCoding
        if writer.needs_objc():
            writer.add('public static var supportsSecureCoding: Bool { true }')
            writer.newline()

            writer.add('public required convenience init?(coder: NSCoder) {')
            writer.push_indent()
            writer.add('guard let serializedData = coder.decodeData() else { return nil }')
            writer.add('do {')
            writer.push_indent()
            writer.add('try self.init(serializedData: serializedData)')
            writer.pop_indent()
            writer.add('} catch {')
            writer.push_indent()
            writer.add('owsFailDebug("Failed to decode serialized data \\(error)")')
            writer.add('return nil')
            writer.pop_indent()
            writer.add('}')
            writer.pop_indent()
            writer.add('}')
            writer.newline()

            writer.add('public func encode(with coder: NSCoder) {')
            writer.push_indent()
            writer.add('do {')
            writer.push_indent()
            writer.add('coder.encode(try serializedData())')
            writer.pop_indent()
            writer.add('} catch {')
            writer.push_indent()
            writer.add('owsFailDebug("Failed to encode serialized data \\(error)")')
            writer.pop_indent()
            writer.add('}')
            writer.pop_indent()
            writer.add('}')
            writer.newline()

        # description
        if writer.needs_objc():
            writer.add_objc()
            writer.add('public override var debugDescription: String {')
        else:
            writer.add('public var debugDescription: String {')
        writer.push_indent()
        writer.add('return "\(proto)"')
        writer.pop_indent()
        writer.add('}')
        writer.newline()

        writer.pop_context()

        writer.rstrip()
        writer.add('}')
        writer.newline()
        self.generate_builder(writer)
        self.generate_debug_extension(writer)

    def generate_debug_extension(self, writer):
        writer.add('#if TESTABLE_BUILD')
        writer.newline()
        with writer.braced('extension %s' % self.swift_name) as writer:
            writer.add_objc()
            with writer.braced('public func serializedDataIgnoringErrors() -> Data?') as writer:
                writer.add('return try! self.serializedData()')

        writer.newline()

        with writer.braced('extension %s' % self.swift_builder_name ) as writer:
            writer.add_objc()
            with writer.braced('public func buildIgnoringErrors() -> %s?' % self.swift_name) as writer:
                if self.can_init_throw():
                    writer.add('return try! self.build()')
                else:
                    writer.add('return self.buildInfallibly()')

        writer.newline()
        writer.add('#endif')
        writer.newline()

    def generate_builder(self, writer):

        wrapped_swift_name = self.derive_wrapped_swift_name()

        # Required Fields
        required_fields = [field for field in self.fields() if field.is_required]
        required_init_params = []
        required_init_args = []
        if len(required_fields) > 0:
            for field in required_fields:
                if field.rules == 'repeated':
                    param_type = '[' + self.base_swift_type_for_field(field) + ']'
                else:
                    param_type = self.base_swift_type_for_field(field)
                required_init_params.append('%s: %s' % ( field.name_swift, param_type) )
                required_init_args.append('%s: %s' % ( field.name_swift, field.name_swift) )

        with writer.braced('extension %s' % self.swift_name) as writer:
            # Convenience accessor.
            writer.add_objc()
            with writer.braced('public static func builder(%s) -> %s' % (
                    ', '.join(required_init_params),
                    self.swift_builder_name,
                    )) as writer:
                writer.add('return %s(%s)' % (self.swift_builder_name, ', '.join(required_init_args), ))
            writer.newline()

            # asBuilder()
            writer.add('// asBuilder() constructs a builder that reflects the proto\'s contents.')
            writer.add_objc()
            with writer.braced('public func asBuilder() -> %s' % (
                    self.swift_builder_name,
                    )) as writer:
                if writer.needs_objc():
                    writer.add('let builder = %s(%s)' % (self.swift_builder_name, ', '.join(required_init_args), ))
                else:
                    writer.add('var builder = %s(%s)' % (self.swift_builder_name, ', '.join(required_init_args), ))

                for field in self.fields():
                    if field.is_required:
                        continue

                    accessor_name = field.name_swift
                    accessor_name = 'set' + accessor_name[0].upper() + accessor_name[1:]

                    can_be_optional = not self.is_field_primitive(field)
                    if field.rules == 'repeated':
                        writer.add('builder.%s(%s)' % ( accessor_name, field.name_swift, ))
                    elif can_be_optional:
                        writer.add('if let _value = %s {' % field.name_swift )
                        writer.push_indent()
                        writer.add('builder.%s(_value)' % ( accessor_name, ))
                        writer.pop_indent()
                        writer.add('}')
                    else:
                        writer.add('if %s {' % field.has_accessor_name() )
                        writer.push_indent()
                        writer.add('builder.%s(%s)' % ( accessor_name, field.name_swift, ))
                        writer.pop_indent()
                        writer.add('}')

                writer.add('if let _value = unknownFields {')
                writer.push_indent()
                writer.add('builder.setUnknownFields(_value)')
                writer.pop_indent()
                writer.add('}')

                writer.add('return builder')
        writer.newline()

        if writer.needs_objc():
            writer.add_objc()
            writer.add('public class %s: NSObject {' % self.swift_builder_name)
        else:
            writer.add('public struct %s {' % self.swift_builder_name)
        writer.newline()

        writer.push_context(self.proto_name, self.swift_name)

        writer.add('private var proto = %s()' % wrapped_swift_name)
        writer.newline()

        # Initializer
        if writer.needs_objc():
            writer.add_objc()
            writer.add('fileprivate override init() {}')
        else:
            writer.add('fileprivate init() {}')
        writer.newline()

        # Required-Field Initializer
        if len(required_fields) > 0:
            # writer.add('// Initializer for required fields')
            writer.add_objc()
            writer.add('fileprivate init(%s) {' % ', '.join(required_init_params))
            writer.push_indent()
            if writer.needs_objc():
                writer.add('super.init()')
            writer.newline()
            for field in required_fields:
                accessor_name = field.name_swift
                accessor_name = 'set' + accessor_name[0].upper() + accessor_name[1:]
                writer.add('%s(%s)' % ( accessor_name, field.name_swift, ) )
            writer.pop_indent()
            writer.add('}')
            writer.newline()

        # Setters
        for field in self.fields():
            if field.rules == 'repeated':
                # Add
                accessor_name = field.name_swift
                accessor_name = 'add' + accessor_name[0].upper() + accessor_name[1:]
                if writer.needs_objc():
                    writer.add_objc()
                    writer.add('public func %s(_ valueParam: %s) {' % ( accessor_name, self.base_swift_type_for_field(field), ))
                else:
                    writer.add('public mutating func %s(_ valueParam: %s) {' % ( accessor_name, self.base_swift_type_for_field(field), ))
                writer.push_indent()
                if self.is_field_an_enum(field):
                    enum_context = self.context_for_proto_type(field)
                    param = ('%s(valueParam)' % enum_context.unwrap_func_name() )
                elif self.is_field_oneof(field):
                    oneof_context = self.context_for_proto_type(field)
                    param = ('%s(valueParam)' % oneof_context.unwrap_func_name() )
                elif self.is_field_a_proto(field):
                    param = 'valueParam.proto'
                else:
                    param = 'valueParam'
                writer.add('proto.%s.append(%s)' % ( field.name_swift, param ) )
                writer.pop_indent()
                writer.add('}')
                writer.newline()

                # Set
                accessor_name = field.name_swift
                accessor_name = 'set' + accessor_name[0].upper() + accessor_name[1:]
                if writer.needs_objc():
                    writer.add_objc()
                    writer.add('public func %s(_ wrappedItems: [%s]) {' % ( accessor_name, self.base_swift_type_for_field(field), ))
                else:
                    writer.add('public mutating func %s(_ wrappedItems: [%s]) {' % ( accessor_name, self.base_swift_type_for_field(field), ))
                writer.push_indent()
                if self.is_field_an_enum(field):
                    enum_context = self.context_for_proto_type(field)
                    writer.add('proto.%s = wrappedItems.map { %s($0) }' % ( field.name_swift, enum_context.unwrap_func_name(), ) )
                elif self.is_field_a_proto(field):
                    writer.add('proto.%s = wrappedItems.map { $0.proto }' % ( field.name_swift, ) )
                else:
                    writer.add('proto.%s = wrappedItems' % ( field.name_swift, ) )
                writer.pop_indent()
                writer.add('}')
                writer.newline()
            else:
                accessor_name = field.name_swift
                accessor_name = 'set' + accessor_name[0].upper() + accessor_name[1:]

                # for fields that are supported as optionals in objc, we will add an objc only setter that takes an optional value
                can_field_be_optional_objc = self.can_field_be_optional_objc(field)
                if can_field_be_optional_objc:
                    writer.add_objc()
                    writer.add('@available(swift, obsoleted: 1.0)') # Don't allow using this function in Swift
                    if writer.needs_objc():
                        writer.add('public func %s(_ valueParam: %s) {' % ( accessor_name, self.swift_type_for_field(field) ))
                    else:
                        writer.add('public mutating func %s(_ valueParam: %s) {' % ( accessor_name, self.swift_type_for_field(field) ))
                    writer.push_indent()
                    writer.add('guard let valueParam = valueParam else { return }')

                    if self.is_field_an_enum(field):
                        enum_context = self.context_for_proto_type(field)
                        writer.add('proto.%s = %s(valueParam)' % ( field.name_swift, enum_context.unwrap_func_name(), ) )
                    elif self.is_field_oneof(field):
                        oneof_context = self.context_for_proto_type(field)
                        writer.add('proto.%s = %s(valueParam)' % ( field.name_swift, oneof_context.unwrap_func_name(), ) )
                    elif self.is_field_a_proto(field):
                        writer.add('proto.%s = valueParam.proto' % ( field.name_swift, ) )
                    else:
                        if field.name.endswith('E164') and field.proto_type == 'string':
                            writer.add('if let valueParam = valueParam.nilIfEmpty {')
                            writer.push_indent()
                            writer.add('owsAssertDebug(valueParam.isStructurallyValidE164)')
                            writer.pop_indent()
                            writer.add('}')
                            writer.newline()
                        
                        writer.add('proto.%s = valueParam' % ( field.name_swift, ) )

                    writer.pop_indent()
                    writer.add('}')
                    writer.newline()

                # Only allow the nonnull setter in objc if the field can't be optional
                if not can_field_be_optional_objc:
                    writer.add_objc()
                if writer.needs_objc():
                    writer.add('public func %s(_ valueParam: %s) {' % ( accessor_name, self.base_swift_type_for_field(field) ))
                else:
                    writer.add('public mutating func %s(_ valueParam: %s) {' % ( accessor_name, self.base_swift_type_for_field(field) ))
                writer.push_indent()

                if self.is_field_an_enum(field):
                    enum_context = self.context_for_proto_type(field)
                    writer.add('proto.%s = %s(valueParam)' % ( field.name_swift, enum_context.unwrap_func_name(), ) )
                elif self.is_field_oneof(field):
                    oneof_context = self.context_for_proto_type(field)
                    writer.add('proto.%s = %s(valueParam)' % ( field.name_swift, oneof_context.unwrap_func_name(), ) )
                elif self.is_field_a_proto(field):
                    writer.add('proto.%s = valueParam.proto' % ( field.name_swift, ) )
                else:
                    if field.name.endswith('E164') and field.proto_type == 'string':
                        writer.add('if let valueParam = valueParam.nilIfEmpty {')
                        writer.push_indent()
                        writer.add('owsAssertDebug(valueParam.isStructurallyValidE164)')
                        writer.pop_indent()
                        writer.add('}')
                        writer.newline()
                    writer.add('proto.%s = valueParam' % ( field.name_swift, ) )

                writer.pop_indent()
                writer.add('}')
                writer.newline()

        # Unknown fields setter
        if writer.needs_objc():
            writer.add('public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {')
        else:
            writer.add('public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {')
        writer.push_indent()
        writer.add('proto.unknownFields = unknownFields')
        writer.pop_indent()
        writer.add('}')
        writer.newline()

        # build() func
        writer.add_objc()
        writer.add('public func build() throws -> %s {' % self.swift_name)
        writer.push_indent()
        if self.can_init_throw():
            writer.add('return try %s(proto)' % self.swift_name)
        else:
            writer.add('return %s(proto)' % self.swift_name)
        writer.pop_indent()
        writer.add('}')
        writer.newline()

        if not self.can_init_throw():
            writer.add_objc()
            writer.add('public func buildInfallibly() -> %s {' % self.swift_name)
            writer.push_indent()
            writer.add('return %s(proto)' % self.swift_name)
            writer.pop_indent()
            writer.add('}')
            writer.newline()

        # buildSerializedData() func
        writer.add_objc()
        writer.add('public func buildSerializedData() throws -> Data {')
        writer.push_indent()
        writer.add('return try %s(proto).serializedData()' % self.swift_name)
        writer.pop_indent()
        writer.add('}')
        writer.newline()

        writer.pop_context()

        writer.rstrip()
        writer.add('}')
        writer.newline()

class EnumContext(BaseContext):
    def __init__(self, args, parent, proto_name):
        BaseContext.__init__(self)

        self.args = args
        self.parent = parent
        self.proto_name = proto_name

        # self.item_names = set()
        # self.item_indices = set()
        self.item_map = {}

    def derive_wrapped_swift_name(self):
        # return BaseContext.derive_wrapped_swift_name(self) + 'Enum'
        result = BaseContext.derive_wrapped_swift_name(self)
        if self.proto_name == 'Type':
            result = result + 'Enum'
        return result

    def fully_qualify_wrappers(self):
        return False

    def wrap_func_name(self):
        if self.fully_qualify_wrappers():
            return '%s.%sWrap' % ( self.parent.swift_name, self.swift_name, )
        return '%sWrap' % ( self.swift_name, )

    def unwrap_func_name(self):
        if self.fully_qualify_wrappers():
            return '%s.%sUnwrap' % ( self.parent.swift_name, self.swift_name, )
        return '%sUnwrap' % ( self.swift_name, )

    def item_names(self):
        return self.item_map.values()

    def item_indices(self):
        return self.item_map.keys()

    def prepare(self):
        self.swift_name = self.derive_swift_name()

        for child in self.children():
            child.prepare()

    def case_pairs(self):
        indices = [int(index) for index in self.item_indices()]
        indices = sorted(indices)
        result = []
        for index in indices:
            index_str = str(index)
            item_name = self.item_map[index_str]
            case_name = lower_camel_case(item_name)
            result.append( (case_name, index_str,) )
        return result

    def default_value(self):
        for case_name, case_index in self.case_pairs():
            return '.' + case_name

    def generate(self, writer):

        writer.add('// MARK: - %s' % self.swift_name)
        writer.newline() 

        if proto_syntax == 'proto3':
            # proto3 enums are completely different.
            # Swift-only, with Int rawValue.
            writer.add('public enum %s: SwiftProtobuf.Enum {' % self.swift_name)

            writer.push_context(self.proto_name, self.swift_name)

            writer.add('public typealias RawValue = Int')

            max_case_index = 0
            for case_name, case_index in self.case_pairs():
                if case_name in ['default', 'true', 'false']:
                    case_name = "`%s`" % case_name
                writer.add('case %s // %s' % ( case_name, case_index, ) )
                max_case_index = max(max_case_index, int(case_index))
                
            writer.add('case UNRECOGNIZED(Int)')
    
    
            writer.newline()
            writer.add('public init() {')
            writer.push_indent()
            for case_name, case_index in self.case_pairs():
                writer.add('self = .%s' % case_name)
                break
            writer.pop_indent()
            writer.add('}')

            writer.newline()
            writer.add('public init?(rawValue: Int) {')
            writer.push_indent()
            writer.add('switch rawValue {')
            writer.push_indent()
            for case_name, case_index in self.case_pairs():
                writer.add('case %s: self = .%s' % (case_index, case_name) )
            writer.add('default: self = .UNRECOGNIZED(rawValue)')
            writer.pop_indent()
            writer.add('}')
            writer.pop_indent()
            writer.add('}')

            writer.newline()
            writer.add('public var rawValue: Int {')
            writer.push_indent()
            writer.add('switch self {')
            writer.push_indent()
            for case_name, case_index in self.case_pairs():
                writer.add('case .%s: return %s' % ( case_name, case_index, ) )
            writer.add('case .UNRECOGNIZED(let i): return i')
            writer.pop_indent()
            writer.add('}')
            writer.pop_indent()
            writer.add('}')

            writer.pop_context()

            writer.rstrip()
            writer.add('}')
            writer.newline()
        else:
            writer.add_objc()
            writer.add('public enum %s: Int32 {' % self.swift_name)

            writer.push_context(self.proto_name, self.swift_name)

            max_case_index = 0
            for case_name, case_index in self.case_pairs():
                if case_name in ['default', 'true', 'false']:
                    case_name = "`%s`" % case_name
                writer.add('case %s = %s' % (case_name, case_index,))
                max_case_index = max(max_case_index, int(case_index))

            writer.pop_context()

            writer.rstrip()
            writer.add('}')
            writer.newline()

            
        wrapped_swift_name = self.derive_wrapped_swift_name()
        writer.add('private func %sWrap(_ value: %s) -> %s {' % ( self.swift_name, wrapped_swift_name, self.swift_name, ) )
        writer.push_indent()
        writer.add('switch value {')
        for case_name, case_index in self.case_pairs():
            writer.add('case .%s: return .%s' % (case_name, case_name,))
        if proto_syntax == 'proto3':
            writer.add('case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)')
            
        writer.add('}')
        writer.pop_indent()
        writer.add('}')
        writer.newline()
        writer.add('private func %sUnwrap(_ value: %s) -> %s {' % ( self.swift_name, self.swift_name, wrapped_swift_name, ) )
        writer.push_indent()
        writer.add('switch value {')
        for case_name, case_index in self.case_pairs():
            writer.add('case .%s: return .%s' % (case_name, case_name,))
        if proto_syntax == 'proto3':
            writer.add('case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)')
        writer.add('}')
        writer.pop_indent()
        writer.add('}')
        writer.newline()


class OneOfContext(BaseContext):
    def __init__(self, args, parent, proto_name):
        BaseContext.__init__(self)

        self.args = args
        self.parent = parent
        self.proto_name = camel_case(proto_name)

        self.item_type_map = {}
        self.item_index_map = {}

    def derive_swift_name(self):
        names = self.inherited_proto_names()
        names.insert(-1, 'OneOf')
        return self.args.wrapper_prefix + ''.join(names)

    def derive_wrapped_swift_name(self):
        names = self.inherited_proto_names()
        names[-1] = 'OneOf_' + self.proto_name
        return self.args.proto_prefix + '_' + '.'.join(names)

    def qualified_proto_name(self):
        names = self.inherited_proto_names()
        names[-1] = 'OneOf_' + self.proto_name
        return '.'.join(names)

    def item_names(self):
        return self.item_index_map.values()

    def item_indices(self):
        return self.item_index_map.keys()

    def sorted_item_indices(self):
        indices = [int(index) for index in self.item_indices()]
        return sorted(indices)

    def last_index(self):
        return self.sorted_item_indices()[-1]

    def wrap_func_name(self):
        return '%sWrap' % ( self.swift_name, )

    def unwrap_func_name(self):
        return '%sUnwrap' % ( self.swift_name, )

    def prepare(self):
        self.swift_name = self.derive_swift_name()

    def context_for_proto_type(self, proto_type):
        for candidate in self.all_known_contexts(should_deep_search=False):
            if candidate.proto_name == proto_type:
                return candidate
            if candidate.qualified_proto_name() == proto_type:
                return candidate

        return None

    def case_tuples(self):
        result = []
        for index in self.sorted_item_indices():
            index_str = str(index)
            item_name = self.item_index_map[index_str]
            item_type = self.item_type_map[item_name]
            case_name = lower_camel_case(item_name)
            case_type = swift_type_for_proto_primitive_type(item_type)
            case_throws = False
            if case_type is None:
                case_type = self.context_for_proto_type(item_type).swift_name
                case_throws = self.is_field_a_proto_whose_init_throws(item_type)
            result.append( (case_name, case_type, case_throws) )
        return result

    def generate(self, writer):

        writer.add('// MARK: - %s' % self.swift_name)
        writer.newline() 

        # proto3 enums are completely different.
        # Swift-only, with Int rawValue.
        writer.add('public enum %s {' % self.swift_name)

        writer.push_context(self.proto_name, self.swift_name)

        for case_name, case_type, _ in self.case_tuples():
            writer.add('case %s(%s)' % ( case_name, case_type, ) )


        writer.pop_context()

        writer.rstrip()
        writer.add('}')
        writer.newline()

        wrapped_swift_name = self.derive_wrapped_swift_name()
        # TODO: Only mark this throws if one of the cases throws.
        writer.add('private func %sWrap(_ value: %s) throws -> %s {' % ( self.swift_name, wrapped_swift_name, self.swift_name, ) )
        writer.push_indent()
        writer.add('switch value {')
        for case_name, case_type, case_throws in self.case_tuples():
            if is_swift_primitive_type(case_type):
                writer.add('case .%s(let value): return .%s(value)' % (case_name, case_name, ) )
            elif case_throws:
                writer.add('case .%s(let value): return .%s(try %s(value))' % (case_name, case_name, case_type, ) )
            else:
                writer.add('case .%s(let value): return .%s(%s(value))' % (case_name, case_name, case_type, ) )
            
        writer.add('}')
        writer.pop_indent()
        writer.add('}')
        writer.newline()

        writer.add('private func %sUnwrap(_ value: %s) -> %s {' % ( self.swift_name, self.swift_name, wrapped_swift_name, ) )
        writer.push_indent()
        writer.add('switch value {')
        for case_name, case_type, case_throws in self.case_tuples():
            if is_swift_primitive_type(case_type):
                writer.add('case .%s(let value): return .%s(value)' % (case_name, case_name,))
            else:
                writer.add('case .%s(let value): return .%s(value.proto)' % (case_name, case_name,))
        writer.add('}')
        writer.pop_indent()
        writer.add('}')
        writer.newline()


class LineParser:
    def __init__(self, text):
        self.lines = text.split('\n')
        self.lines.reverse()
        self.next_line_comments = []

    def __next__(self):
        # lineParser = LineParser(text.split('\n'))

        self.next_line_comments = []
        while len(self.lines) > 0:
            line = self.lines.pop()
            line = line.strip()
            # if not line:
            #     continue

            comment_index = line.find('//')
            if comment_index >= 0:
                comment = line[comment_index + len('//'):].strip()
                line = line[:comment_index].strip()
                if not line:
                    if comment:
                        self.next_line_comments.append(comment)
            else:
                if not line:
                    self.next_line_comments = []

            if not line:
                continue

            # if args.verbose:
            #     print 'line:', line

            return line
        raise StopIteration()


def parse_enum(args, proto_file_path, parser, parent_context, enum_name):

    # if args.verbose:
    #     print '# enum:', enum_name

    context = EnumContext(args, parent_context, enum_name)

    allow_alias = False
    while True:
        try:
            line = next(parser)
        except StopIteration:
            raise Exception('Incomplete enum: %s' % proto_file_path)

        if line == 'option allow_alias = true;':
            allow_alias = True
            continue

        if line == '}':
            # if args.verbose:
            #     print
            parent_context.enums.append(context)
            return

        if reserved_regex.search(line):
            continue

        item_match = enum_item_regex.search(line)
        if item_match:
            item_name = item_match.group(1).strip()
            item_index = item_match.group(2).strip()

            # if args.verbose:
            #     print '\t enum item[%s]: %s' % (item_index, item_name)

            if item_name in context.item_names():
                raise Exception('Duplicate enum name[%s]: %s' % (proto_file_path, item_name))

            if item_index in context.item_indices():
                if allow_alias:
                    continue
                raise Exception('Duplicate enum index[%s]: %s' % (proto_file_path, item_name))

            context.item_map[item_index] = item_name

            continue

        raise Exception('Invalid enum syntax[%s]: "%s"' % (proto_file_path, line))


def parse_oneof(args, proto_file_path, parser, parent_context, oneof_name):

    # if args.verbose:
    #     print '# oneof:', oneof_name

    if oneof_name in parent_context.field_names():
        raise Exception('Duplicate message field name[%s]: %s' % (proto_file_path, oneof_name))

    context = OneOfContext(args, parent_context, oneof_name)

    oneof_index = None

    while True:
        try:
            line = next(parser)
        except StopIteration:
            raise Exception('Incomplete oneof: %s' % proto_file_path)

        if line == '}':
            break

        item_match = oneof_item_regex.search(line)
        if item_match:
            item_type = item_match.group(1).strip()
            item_name = item_match.group(2).strip()
            item_index = item_match.group(3).strip()

            # if args.verbose:
            #     print '\t oneof item[%s]: %s' % (item_index, item_name)

            if item_name in context.item_names():
                raise Exception('Duplicate oneof name[%s]: %s' % (proto_file_path, item_name))

            if item_index in context.item_indices():
                raise Exception('Duplicate oneof index[%s]: %s' % (proto_file_path, item_name))

            context.item_type_map[item_name] = item_type
            context.item_index_map[item_index] = item_name

            continue

        raise Exception('Invalid oneof syntax[%s]: "%s"' % (proto_file_path, line))

    parent_context.oneofs.append(context)
    return context


def optional_match_group(match, index):
    group = match.group(index)
    if group is None:
        return None
    return group.strip()


def parse_message(args, proto_file_path, parser, parent_context, message_name):

    # if args.verbose:
    #     print '# message:', message_name

    context = MessageContext(args, parent_context, message_name)

    sort_index = 0
    while True:
        try:
            line = next(parser)
        except StopIteration:
            raise Exception('Incomplete message: %s' % proto_file_path)

        field_comments = parser.next_line_comments

        if line == '}':
            # if args.verbose:
            #     print
            parent_context.messages.append(context)
            return

        enum_match = enum_regex.search(line)
        if enum_match:
            enum_name = enum_match.group(1).strip()
            parse_enum(args, proto_file_path, parser, context, enum_name)
            continue

        message_match = message_regex.search(line)
        if message_match:
            message_name = message_match.group(1).strip()
            parse_message(args, proto_file_path, parser, context, message_name)
            continue

        if proto_syntax == 'proto3':
            oneof_match = oneof_regex.search(line)
            if oneof_match:
                oneof_name = oneof_match.group(1).strip()
                oneof_context = parse_oneof(args, proto_file_path, parser, context, oneof_name)
                oneof_index = oneof_context.last_index()
                oneof_type = oneof_context.derive_swift_name()
                context.field_map[oneof_index] = MessageField(oneof_name, oneof_index, 'optional', oneof_type, None, sort_index, False)
                sort_index = sort_index + 1
                continue

        if reserved_regex.search(line):
            continue

        # Examples:
        #
        # optional bytes  id          = 1;
        # optional bool              isComplete = 2 [default = false];
        #
        # NOTE: optional and required are not valid in proto3.
        item_match = message_item_regex.search(line)
        if item_match:
            # print 'item_rules:', item_match.groups()
            item_rules = optional_match_group(item_match, 1)
            item_type = optional_match_group(item_match, 2)
            item_name = optional_match_group(item_match, 3)
            item_index = optional_match_group(item_match, 4)
            # item_defaults_1 = optional_match_group(item_match, 5)
            item_default = optional_match_group(item_match, 6)

            if proto_syntax == 'proto3':
                if item_rules is None:
                    item_rules = 'optional'
                elif item_rules == 'repeated':
                    pass
                else:
                    raise Exception('Unexpected rule[%s]: %s' % (proto_file_path, item_rules))

            # print 'item_rules:', item_rules
            # print 'item_type:', item_type
            # print 'item_name:', item_name
            # print 'item_index:', item_index
            # print 'item_default:', item_default

            message_field = {
                'rules': item_rules,
                'type': item_type,
                'name': item_name,
                'index': item_index,
                'default': item_default,
                'field_comments': field_comments,
            }
            # print 'message_field:', message_field

            # if args.verbose:
            #     print '\t message field[%s]: %s' % (item_index, str(message_field))

            if item_name in context.field_names():
                raise Exception('Duplicate message field name[%s]: %s' % (proto_file_path, item_name))
            # context.field_names.add(item_name)

            if item_index in context.field_indices():
                raise Exception('Duplicate message field index[%s]: %s' % (proto_file_path, item_name))
            # context.field_indices.add(item_index)

            is_required = '@required' in field_comments
            # if is_required:
            #     print 'is_required:', item_name
            # print 'item_name:', item_name, 'item_type:', item_type

            context.field_map[item_index] = MessageField(item_name, item_index, item_rules, item_type, item_default, sort_index, is_required)

            sort_index = sort_index + 1

            continue

        raise Exception('Invalid message syntax[%s]: %s' % (proto_file_path, line))


def process_proto_file(args, proto_file_path, dst_file_path):
    with open(proto_file_path, 'rt') as f:
        text = f.read()

    text = multiline_comment_regex.sub('', text)

    parser = LineParser(text)

    # lineParser = LineParser(text.split('\n'))

    context = FileContext(args)

    while True:
        try:
            line = next(parser)
        except StopIteration:
            break

        enum_match = enum_regex.search(line)
        if enum_match:
            enum_name = enum_match.group(1).strip()
            parse_enum(args, proto_file_path, parser, context, enum_name)
            continue

        syntax_match = syntax_regex.search(line)
        if syntax_match:
            global proto_syntax
            proto_syntax = syntax_match.group(1).strip()
            if args.verbose:
                print('Syntax:', proto_syntax)
            continue

        if option_regex.search(line):
            if args.verbose:
                print('# Ignoring option')
            continue

        package_match = package_regex.search(line)
        if package_match:
            if args.package:
                raise Exception('More than one package statement: %s' % proto_file_path)
            args.package = package_match.group(1).strip()

            if args.verbose:
                print('# package:', args.package)
            continue

        message_match = message_regex.search(line)
        if message_match:
            message_name = message_match.group(1).strip()
            parse_message(args, proto_file_path, parser, context, message_name)
            continue

        raise Exception('Invalid syntax[%s]: %s' % (proto_file_path, line))

    writer = LineWriter(args)
    context.prepare()
    context.generate(writer)
    output = writer.join()
    with open(dst_file_path, 'wt') as f:
        f.write(output)


if __name__ == "__main__":

    parser = argparse.ArgumentParser(description='Protocol Buffer Swift Wrapper Generator.')
    parser.add_argument('--proto-dir', help='dir path of the proto schema file.')
    parser.add_argument('--proto-file', help='filename of the proto schema file.')
    parser.add_argument('--wrapper-prefix', help='name prefix for generated wrappers.')
    parser.add_argument('--proto-prefix', help='name prefix for proto bufs.')
    parser.add_argument('--dst-dir', help='path to the destination directory.')
    parser.add_argument('--verbose', action='store_true', help='enables verbose logging')
    args = parser.parse_args()

    if args.verbose:
        print('args:', args)

    proto_file_path = os.path.abspath(os.path.join(args.proto_dir, args.proto_file))
    if not os.path.exists(proto_file_path):
        raise Exception('File does not exist: %s' % proto_file_path)

    dst_dir_path = os.path.abspath(args.dst_dir)
    if not os.path.exists(dst_dir_path):
        raise Exception('Destination does not exist: %s' % dst_dir_path)

    dst_file_path = os.path.join(dst_dir_path, "%s.swift" % args.wrapper_prefix)

    if args.verbose:
        print('dst_file_path:', dst_file_path)

    args.package = None
    process_proto_file(args, proto_file_path, dst_file_path)

    # print 'complete.'

