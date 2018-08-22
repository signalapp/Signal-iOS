#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os
import sys
import subprocess 
import datetime
import argparse
import commands
import re


git_repo_path = os.path.abspath(subprocess.check_output(['git', 'rev-parse', '--show-toplevel']).strip())

        
def lowerCamlCaseForUnderscoredText(name):
    splits = name.split('_')
    splits = [split.title() for split in splits]
    splits[0] = splits[0].lower()
    return ''.join(splits)
        

# The generated code for "Apple Swift Protos" suppresses
# adjacent capital letters in lowerCamlCase.
def lowerCamlCaseForUnderscoredText_wrapped(name):
    chars = []
    lastWasUpper = False
    for char in name:
        if lastWasUpper:
            char = char.lower()
        chars.append(char)
        lastWasUpper = (char.upper() == char)
    result = ''.join(chars)
    if result.endswith('Id'):
        result = result[:-2] + 'ID'
    return result

# Provides conext for writing an indented block surrounded by braces.
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
        candidates = []
        candidates.extend(self.descendents())
        candidates.extend(self.siblings())
        for ancestor in self.ancestors():
            if ancestor.proto_name is None:
                # Ignore the root context
                continue
            candidates.append(ancestor)
            candidates.extend(ancestor.siblings())

        for candidate in candidates:
            if candidate.proto_name == field.proto_type:
                return candidate
        
        return None                
        
    
    def base_swift_type_for_field(self, field):
    
        if field.proto_type == 'string':
            return 'String'
        elif field.proto_type == 'uint64':
            return 'UInt64'            
        elif field.proto_type == 'uint32':
            return 'UInt32'
        elif field.proto_type == 'fixed64':
            return 'UInt64'
        elif field.proto_type == 'bool':
            return 'Bool'
        elif field.proto_type == 'bytes':
            return 'Data'
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
            'bool', )
        
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
            return False
        else:
            return True
        
    def is_field_an_enum(self, field):
        matching_context = self.context_for_proto_type(field)
        if matching_context is not None:
            if type(matching_context) is EnumContext:
                return True
        return False
        
    def is_field_a_proto(self, field):
        matching_context = self.context_for_proto_type(field)
        if matching_context is not None:
            if type(matching_context) is MessageContext:
                return True
        return False
        
    def default_value_for_field(self, field):
        if field.rules == 'repeated':
            return '[]'
        
        if field.default_value is not None and len(field.default_value) > 0:
            return field.default_value

        if field.rules == 'optional':
            can_be_optional = self.can_field_be_optional(field)
            if can_be_optional:
                return 'nil'
        
        if field.proto_type == 'uint64':
            return '0'
        elif field.proto_type == 'uint32':
            return '0'
        elif field.proto_type == 'fixed64':
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
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
''')

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
        return name
        
class MessageContext(BaseContext):
    def __init__(self, args, parent, proto_name):
        BaseContext.__init__(self)

        self.args = args
        self.parent = parent
        
        self.proto_name = proto_name

        self.messages = []
        self.enums = []
        
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
        return self.enums + self.messages
        
    def prepare(self):
        self.swift_name = self.derive_swift_name()
        self.swift_builder_name = "%sBuilder" % self.swift_name
        
        for child in self.children():
            child.prepare()
        
    def generate(self, writer):
        for child in self.messages:
            child.generate(writer)
    
        writer.add('// MARK: - %s' % self.swift_name)
        writer.newline()
        
        writer.add('@objc public class %s: NSObject {' % self.swift_name)
        writer.newline()
        
        writer.push_context(self.proto_name, self.swift_name)
        
        if self.args.add_log_tag:
            writer.add('fileprivate static let logTag = "%s"' % self.swift_name)
            writer.add('fileprivate let logTag = "%s"' % self.swift_name)
            writer.newline()
        
        for child in self.enums:
            child.generate(writer)

        wrapped_swift_name = self.derive_wrapped_swift_name()

        # Prepare fields
        explict_fields = []
        implict_fields = []
        for field in self.fields():
            field.type_swift = self.swift_type_for_field(field)
            field.type_swift_not_optional = self.swift_type_for_field(field, suppress_optional=True)
            field.name_swift = lowerCamlCaseForUnderscoredText_wrapped(field.name)
            
            is_explicit = False
            if field.is_required:
                is_explicit = True
            elif self.is_field_a_proto(field):
                is_explicit = True
            if is_explicit:
                explict_fields.append(field)
            else:
                implict_fields.append(field)

        self.generate_builder(writer)
        
        writer.add('fileprivate let proto: %s' % wrapped_swift_name )
        writer.newline()
        
        # Property Declarations
        if len(explict_fields) > 0:
            for field in explict_fields:
                type_name = field.type_swift_not_optional if field.is_required else field.type_swift
                writer.add('@objc public let %s: %s' % (field.name_swift, type_name))
                
                if (not field.is_required) and field.rules != 'repeated' and (not self.is_field_a_proto(field)):
                    writer.add('@objc public var %s: Bool {' % field.has_accessor_name() )
                    writer.push_indent()
                    writer.add('return proto.%s' % field.has_accessor_name() )
                    writer.pop_indent()
                    writer.add('}')
                writer.newline()

        if len(implict_fields) > 0:
            for field in implict_fields:
                if field.rules == 'optional':
                    can_be_optional = (not self.is_field_primitive(field)) and (not self.is_field_an_enum(field))
                    if can_be_optional:
                        writer.add('@objc public var %s: %s? {' % (field.name_swift, field.type_swift_not_optional))
                        writer.push_indent()
                        writer.add('guard proto.%s else {' % field.has_accessor_name() )
                        writer.push_indent()
                        writer.add('return nil')
                        writer.pop_indent()
                        writer.add('}')
                        if self.is_field_an_enum(field):
                            enum_context = self.context_for_proto_type(field)
                            writer.add('return %s.%sWrap(proto.%s)' % ( enum_context.parent.swift_name, enum_context.swift_name, field.name_swift, ) )
                        else:
                            writer.add('return proto.%s' % field.name_swift )
                        writer.pop_indent()
                        writer.add('}')
                    else:
                        writer.add('@objc public var %s: %s {' % (field.name_swift, field.type_swift_not_optional))
                        writer.push_indent()
                        if self.is_field_an_enum(field):
                            enum_context = self.context_for_proto_type(field)
                            writer.add('return %s.%sWrap(proto.%s)' % ( enum_context.parent.swift_name, enum_context.swift_name, field.name_swift, ) )
                        else:
                            writer.add('return proto.%s' % field.name_swift )
                        writer.pop_indent()
                        writer.add('}')

                    writer.add('@objc public var %s: Bool {' % field.has_accessor_name() )
                    writer.push_indent()
                    writer.add('return proto.%s' % field.has_accessor_name() )
                    writer.pop_indent()
                    writer.add('}')
                    writer.newline()
                elif field.rules == 'repeated':
                    writer.add('@objc public var %s: %s {' % (field.name_swift, field.type_swift_not_optional))
                    writer.push_indent()
                    writer.add('return proto.%s' % field.name_swift )
                    writer.pop_indent()
                    writer.add('}')
                    writer.newline()
                else:
                    writer.add('@objc public var %s: %s {' % (field.name_swift, field.type_swift_not_optional))
                    writer.push_indent()
                    if self.is_field_an_enum(field):
                        enum_context = self.context_for_proto_type(field)
                        writer.add('return %sUnwrap(proto.%s)' % ( enum_context.swift_name, field.name_swift, ) )
                    else:
                        writer.add('return proto.%s' % field.name_swift )
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
        writer.pop_indent()
        writer.add('}')
        writer.newline()
 
        # serializedData() func
        writer.extend(('''
@objc
public func serializedData() throws -> Data {
    return try self.proto.serializedData()
}
''').strip())
        writer.newline()

        # parseData() func
        writer.add('@objc public class func parseData(_ serializedData: Data) throws -> %s {' % self.swift_name)
        writer.push_indent()
        writer.add('let proto = try %s(serializedData: serializedData)' % ( wrapped_swift_name, ) )
        writer.add('return try parseProto(proto)')        
        writer.pop_indent()
        writer.add('}')
        writer.newline()

        # parseData() func
        writer.add('fileprivate class func parseProto(_ proto: %s) throws -> %s {' % ( wrapped_swift_name, self.swift_name, ) )
        writer.push_indent()
        
        for field in explict_fields:
            if field.is_required:
            # if self.can_field_be_optional(field):
                writer.add('guard proto.%s else {' % field.has_accessor_name() )
                writer.push_indent()
                writer.add('throw %s.invalidProtobuf(description: "\(logTag) missing required field: %s")' % ( writer.invalid_protobuf_error_name, field.name_swift, ) )   
                writer.pop_indent()
                writer.add('}')
            
                if self.is_field_an_enum(field):
                    # TODO: Assert that rules is empty.
                    enum_context = self.context_for_proto_type(field)
                    writer.add('let %s = %sWrap(proto.%s)' % ( field.name_swift, enum_context.swift_name, field.name_swift, ) )
                elif self.is_field_a_proto(field):
                    writer.add('let %s = try %s.parseProto(proto.%s)' % (field.name_swift, self.base_swift_type_for_field(field), field.name_swift)),
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
                    writer.add('%s = proto.%s.map { %sWrap($0) }' % ( field.name_swift, field.name_swift, enum_context.swift_name, ) )
                elif self.is_field_a_proto(field):
                    writer.add('%s = try proto.%s.map { try %s.parseProto($0) }' % ( field.name_swift, field.name_swift, self.base_swift_type_for_field(field), ) )
                else:
                    writer.add('%s = proto.%s' % ( field.name_swift, field.name_swift, ) )
            else:
                writer.add('if proto.%s {' % field.has_accessor_name() )
                writer.push_indent()
            
                if self.is_field_an_enum(field):
                    # TODO: Assert that rules is empty.
                    enum_context = self.context_for_proto_type(field)
                    writer.add('%s = %sWrap(proto.%s)' % ( field.name_swift, enum_context.swift_name, field.name_swift, ) )
                elif self.is_field_a_proto(field):
                    writer.add('%s = try %s.parseProto(proto.%s)' % (field.name_swift, self.base_swift_type_for_field(field), field.name_swift)),
                else:
                    writer.add('%s = proto.%s' % ( field.name_swift, field.name_swift, ) )
                
                writer.pop_indent()
                writer.add('}')
            writer.newline()

        writer.add('// MARK: - Begin Validation Logic for %s -' % self.swift_name)
        writer.newline()
        
        # Preserve existing validation logic.
        if self.swift_name in args.validation_map:
            validation_block = args.validation_map[self.swift_name]
            if validation_block:
                writer.add_raw(validation_block)
                writer.newline()
        
        writer.add('// MARK: - End Validation Logic for %s -' % self.swift_name)
        writer.newline()
        
        initializer_prefix = 'let result = %s(' % self.swift_name
        initializer_arguments = []
        initializer_arguments.append('proto: proto')
        for field in explict_fields:
            argument = '%s: %s' % (field.name_swift, field.name_swift)
            argument = '\n' + ' ' * len(initializer_prefix) + argument
            initializer_arguments.append(argument)
        initializer_arguments = ', '.join(initializer_arguments)
        writer.extend('%s%s)' % ( initializer_prefix, initializer_arguments, ) )
        writer.add('return result')        
        writer.pop_indent()
        writer.add('}')
        writer.newline()

        # description
        if self.args.add_description:
            writer.add('@objc public override var description: String {')
            writer.push_indent()
            writer.add('var fields = [String]()')
            for field in self.fields():
                writer.add('fields.append("%s: \(proto.%s)")' % ( field.name_swift, field.name_swift, ) )
            writer.add('return "[" + fields.joined(separator: ", ") + "]"')
            writer.pop_indent()
            writer.add('}')
            writer.newline()
            
        writer.pop_context()

        writer.rstrip()
        writer.add('}')
        writer.newline()
        self.generate_debug_extension(writer)

    def generate_debug_extension(self, writer):
        writer.add('#if DEBUG') 
        writer.newline() 
        with writer.braced('extension %s' % self.swift_name) as writer:
            with writer.braced('@objc public func serializedDataIgnoringErrors() -> Data?') as writer:
                writer.add('return try! self.serializedData()')

        writer.newline()
 
        with writer.braced('extension %s.%s' % ( self.swift_name, self.swift_builder_name )) as writer:
            with writer.braced('@objc public func buildIgnoringErrors() -> %s?' % self.swift_name) as writer:
                writer.add('return try! self.build()')

        writer.newline()
        writer.add('#endif')
        writer.newline()
        
    def generate_builder(self, writer):
    
        wrapped_swift_name = self.derive_wrapped_swift_name()
        
        writer.add('// MARK: - %s' % self.swift_builder_name)
        writer.newline()
        
        writer.add('@objc public class %s: NSObject {' % self.swift_builder_name)
        writer.newline()
        
        writer.push_context(self.proto_name, self.swift_name)
        
        writer.add('private var proto = %s()' % wrapped_swift_name)
        writer.newline()
        
        # Initializer
        writer.add('@objc public override init() {}')
        writer.newline()
        
        # Required-Field Initializer
        required_fields = [field for field in self.fields() if field.is_required]
        if len(required_fields) > 0:
            required_init_params = []
            for field in required_fields:
                if field.rules == 'repeated':
                    param_type = '[' + self.base_swift_type_for_field(field) + ']'
                else:
                    param_type = self.base_swift_type_for_field(field)
                required_init_params.append('%s: %s' % ( field.name_swift, param_type) )
            writer.add('// Initializer for required fields')
            writer.add('@objc public init(%s) {' % ', '.join(required_init_params))
            writer.push_indent()
            writer.add('super.init()')
            writer.newline()
            for field in required_fields:
                accessor_name = field.name_swift
                accessor_name = 'set' + accessor_name[0].upper() + accessor_name[1:]
                writer.add('%s(%s)' % ( accessor_name, field.name_swift, ) )
            writer.pop_indent()
            writer.add('}')
            writer.newline()
        
        # # All-Field Initializer
        # if len(required_fields) < len(self.fields()):
        #     init_params = []
        #     for field in self.fields():
        #         if field.is_required:
        #             if field.rules == 'repeated':
        #                 param_type = '[' + self.base_swift_type_for_field(field) + ']'
        #             else:
        #                 param_type = self.base_swift_type_for_field(field)
        #         else:
        #             param_type = field.type_swift
        #         init_params.append('%s: %s' % ( field.name_swift, param_type) )
        #     writer.add('// Initializer for required fields')
        #     writer.add('@objc public init(%s) {' % ', '.join(init_params))
        #     writer.push_indent()
        #     writer.add('super.init()')
        #     writer.newline()
        #     for field in self.fields():
        #         accessor_name = field.name_swift
        #         accessor_name = 'set' + accessor_name[0].upper() + accessor_name[1:]
        #         writer.add('%s(%s)' % ( accessor_name, field.name_swift, ) )
        #     writer.pop_indent()
        #     writer.add('}')
        #     writer.newline()
        
        # Setters
        for field in self.fields():
            if field.rules == 'repeated':
                # Add
                accessor_name = field.name_swift
                accessor_name = 'add' + accessor_name[0].upper() + accessor_name[1:]
                writer.add('@objc public func %s(_ valueParam: %s) {' % ( accessor_name, self.base_swift_type_for_field(field), ))
                writer.push_indent()
                writer.add('var items = proto.%s' % ( field.name_swift, ) )
                
                if self.is_field_an_enum(field):
                    enum_context = self.context_for_proto_type(field)
                    writer.add('items.append(%sUnwrap(valueParam))' % enum_context.swift_name )
                elif self.is_field_a_proto(field):
                    writer.add('items.append(valueParam.proto)')
                else:
                    writer.add('items.append(valueParam)')
                writer.add('proto.%s = items' % ( field.name_swift, ) )
                writer.pop_indent()
                writer.add('}')
                writer.newline()
                
                # Set
                accessor_name = field.name_swift
                accessor_name = 'set' + accessor_name[0].upper() + accessor_name[1:]
                writer.add('@objc public func %s(_ wrappedItems: [%s]) {' % ( accessor_name, self.base_swift_type_for_field(field), ))
                writer.push_indent()
                if self.is_field_an_enum(field):
                    enum_context = self.context_for_proto_type(field)
                    writer.add('proto.%s = wrappedItems.map { %sUnwrap($0) }' % ( field.name_swift, enum_context.swift_name, ) )
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
                writer.add('@objc public func %s(_ valueParam: %s) {' % ( accessor_name, self.base_swift_type_for_field(field), ))
                writer.push_indent()

                if self.is_field_an_enum(field):
                    enum_context = self.context_for_proto_type(field)
                    writer.add('proto.%s = %sUnwrap(valueParam)' % ( field.name_swift, enum_context.swift_name, ) )
                elif self.is_field_a_proto(field):
                    writer.add('proto.%s = valueParam.proto' % ( field.name_swift, ) )
                else:
                    writer.add('proto.%s = valueParam' % ( field.name_swift, ) )
                
                writer.pop_indent()
                writer.add('}')
                writer.newline()
 
        # build() func
        writer.add('@objc public func build() throws -> %s {' % self.swift_name)
        writer.push_indent()
        writer.add('return try %s.parseProto(proto)' % self.swift_name)
        writer.pop_indent()
        writer.add('}')
        writer.newline()

        # buildSerializedData() func
        writer.add('@objc public func buildSerializedData() throws -> Data {')
        writer.push_indent()
        writer.add('return try %s.parseProto(proto).serializedData()' % self.swift_name)
        writer.pop_indent()
        writer.add('}')
        writer.newline()

        # description
        if self.args.add_description:
            writer.add('@objc public override var description: String {')
            writer.push_indent()
            writer.add('var fields = [String]()')
            for field in self.fields():
                writer.add('fields.append("%s: \(proto.%s)")' % ( field.name_swift, field.name_swift, ) )
            writer.add('return "[" + fields.joined(separator: ", ") + "]"')
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
            case_name = lowerCamlCaseForUnderscoredText(item_name)
            result.append( (case_name, index_str,) )
        return result
        
    def default_value(self):
        for case_name, case_index in self.case_pairs():
            return '.' + case_name

    def generate(self, writer):
        
        writer.add('// MARK: - %s' % self.swift_name)
        writer.newline()
        
        writer.add('@objc public enum %s: Int32 {' % self.swift_name)
        
        writer.push_context(self.proto_name, self.swift_name)

        for case_name, case_index in self.case_pairs():
            if case_name == 'default':
                case_name = '`default`'
            writer.add('case %s = %s' % (case_name, case_index,))
        
        writer.pop_context()

        writer.rstrip()
        writer.add('}')
        writer.newline()
        
        wrapped_swift_name = self.derive_wrapped_swift_name()
        writer.add('private class func %sWrap(_ value: %s) -> %s {' % ( self.swift_name, wrapped_swift_name, self.swift_name, ) )
        writer.push_indent()
        writer.add('switch value {')
        for case_name, case_index in self.case_pairs():
            writer.add('case .%s: return .%s' % (case_name, case_name,))
        writer.add('}')
        writer.pop_indent()
        writer.add('}')
        writer.newline()
        writer.add('private class func %sUnwrap(_ value: %s) -> %s {' % ( self.swift_name, self.swift_name, wrapped_swift_name, ) )
        writer.push_indent()
        writer.add('switch value {')
        for case_name, case_index in self.case_pairs():
            writer.add('case .%s: return .%s' % (case_name, case_name,))
        writer.add('}')
        writer.pop_indent()
        writer.add('}')
        writer.newline()
        
 
class LineParser:
    def __init__(self, text):
        self.lines = text.split('\n')
        self.lines.reverse()
        self.next_line_comments = []
    
    def next(self):
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
    
    while True:
        try:
            line = parser.next()
        except StopIteration:
            raise Exception('Incomplete enum: %s' % proto_file_path)
    
        if line == '}':
            # if args.verbose:
            #     print
            parent_context.enums.append(context)
            return

        item_regex = re.compile(r'^(.+?)\s*=\s*(\d+?)\s*;$')
        item_match = item_regex.search(line)
        if item_match:
            item_name = item_match.group(1).strip()
            item_index = item_match.group(2).strip()
        
            # if args.verbose:
            #     print '\t enum item[%s]: %s' % (item_index, item_name)
            
            if item_name in context.item_names():
                raise Exception('Duplicate enum name[%s]: %s' % (proto_file_path, item_name))
            
            if item_index in context.item_indices():
                raise Exception('Duplicate enum index[%s]: %s' % (proto_file_path, item_name))
            
            context.item_map[item_index] = item_name
                
            continue
    
        raise Exception('Invalid enum syntax[%s]: %s' % (proto_file_path, line))
        

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
            line = parser.next()
        except StopIteration:
            raise Exception('Incomplete message: %s' % proto_file_path)
    
        field_comments = parser.next_line_comments
        
        if line == '}':
            # if args.verbose:
            #     print
            parent_context.messages.append(context)
            return

        enum_regex = re.compile(r'^enum\s+(.+?)\s+\{$')
        enum_match = enum_regex.search(line)
        if enum_match:
            enum_name = enum_match.group(1).strip()        
            parse_enum(args, proto_file_path, parser, context, enum_name)
            continue
        
        message_regex = re.compile(r'^message\s+(.+?)\s+\{$')
        message_match = message_regex.search(line)
        if message_match:
            message_name = message_match.group(1).strip()
            parse_message(args, proto_file_path, parser, context, message_name)
            continue

        # Examples:
        #
        # optional bytes  id          = 1;
        # optional bool              isComplete = 2 [default = false];
        item_regex = re.compile(r'^(optional|required|repeated)?\s*([\w\d]+?)\s+([\w\d]+?)\s*=\s*(\d+?)\s*(\[default = (true|false)\])?;$')
        item_match = item_regex.search(line)
        if item_match:
            # print 'item_rules:', item_match.groups()
            item_rules = optional_match_group(item_match, 1)
            item_type = optional_match_group(item_match, 2)
            item_name = optional_match_group(item_match, 3)
            item_index = optional_match_group(item_match, 4)
            # item_defaults_1 = optional_match_group(item_match, 5)
            item_default = optional_match_group(item_match, 6)
    
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
            context.field_map[item_index] = MessageField(item_name, item_index, item_rules, item_type, item_default, sort_index, is_required)
            
            sort_index = sort_index + 1
            
            continue

        raise Exception('Invalid message syntax[%s]: %s' % (proto_file_path, line))
    

def preserve_validation_logic(args, proto_file_path, dst_file_path):
    args.validation_map = {}
    if os.path.exists(dst_file_path):
        with open(dst_file_path, 'rt') as f:
            old_text = f.read()
        validation_start_regex = re.compile(r'// MARK: - Begin Validation Logic for ([^ ]+) -')
        for match in validation_start_regex.finditer(old_text):
            # print 'match'
            name = match.group(1)
            # print '\t name:', name
            start = match.end(0)
            # print '\t start:', start
            end_marker = '// MARK: - End Validation Logic for %s -' % name
            end = old_text.find(end_marker)
            # print '\t end:', end
            if end < start:
                raise Exception('Malformed validation: %s, %s' % ( proto_file_path, name, ) )
            validation_block = old_text[start:end]
            # print '\t validation_block:', validation_block
            
            # Strip trailing whitespace.
            validation_lines = validation_block.split('\n')
            validation_lines = [line.rstrip() for line in validation_lines]
            # Strip leading empty lines.
            while len(validation_lines) > 0 and validation_lines[0] == '':
                validation_lines = validation_lines[1:]
            # Strip trailing empty lines.
            while len(validation_lines) > 0 and validation_lines[-1] == '':
                validation_lines = validation_lines[:-1]
            validation_block = '\n'.join(validation_lines)
            
            if len(validation_block) > 0:
                if args.verbose:
                    print 'Preserving validation logic for:', name
            
            args.validation_map[name] = validation_block
            
            
def process_proto_file(args, proto_file_path, dst_file_path):
    with open(proto_file_path, 'rt') as f:
        text = f.read()
    
    multiline_comment_regex = re.compile(r'/\*.*?\*/', re.MULTILINE|re.DOTALL)
    text = multiline_comment_regex.sub('', text)
    
    syntax_regex = re.compile(r'^syntax ')
    package_regex = re.compile(r'^package\s+(.+);')
    option_regex = re.compile(r'^option ')
    
    parser = LineParser(text)
    
    # lineParser = LineParser(text.split('\n'))
    
    context = FileContext(args)
    
    while True:
        try:
            line = parser.next()
        except StopIteration:
            break

        if syntax_regex.search(line):
            if args.verbose:
                print '# Ignoring syntax'
            continue
        
        if option_regex.search(line):
            if args.verbose:
                print '# Ignoring option'
            continue
        
        package_match = package_regex.search(line)
        if package_match:
            if args.package:
                raise Exception('More than one package statement: %s' % proto_file_path)
            args.package = package_match.group(1).strip()
            
            if args.verbose:
                print '# package:', args.package
            continue
        
        message_regex = re.compile(r'^message\s+(.+?)\s+\{$')
        message_match = message_regex.search(line)
        if message_match:
            message_name = message_match.group(1).strip()
            parse_message(args, proto_file_path, parser, context, message_name)
            continue
    
        raise Exception('Invalid syntax[%s]: %s' % (proto_file_path, line))
    
    preserve_validation_logic(args, proto_file_path, dst_file_path)
    
    writer = LineWriter(args)
    context.prepare()
    context.generate(writer)
    output = writer.join()
    with open(dst_file_path, 'wt') as f:
        f.write(output)
    
    
if __name__ == "__main__":
    
    parser = argparse.ArgumentParser(description='Protocol Buffer Swift Wrapper Generator.')
    # parser.add_argument('--all', action='store_true', help='process all files in or below current dir')
    # parser.add_argument('--path', help='used to specify a path to a file.')
    parser.add_argument('--proto-dir', help='dir path of the proto schema file.')
    parser.add_argument('--proto-file', help='filename of the proto schema file.')
    parser.add_argument('--wrapper-prefix', help='name prefix for generated wrappers.')
    parser.add_argument('--proto-prefix', help='name prefix for proto bufs.')
    parser.add_argument('--dst-dir', help='path to the destination directory.')
    parser.add_argument('--add-log-tag', action='store_true', help='add log tag properties.')
    parser.add_argument('--add-description', action='store_true', help='add log tag properties.')
    parser.add_argument('--verbose', action='store_true', help='enables verbose logging')
    args = parser.parse_args()
    
    if args.verbose:
        print 'args:', args
    
    proto_file_path = os.path.abspath(os.path.join(args.proto_dir, args.proto_file))
    if not os.path.exists(proto_file_path):
        raise Exception('File does not exist: %s' % proto_file_path)
    
    dst_dir_path = os.path.abspath(args.dst_dir)
    if not os.path.exists(dst_dir_path):
        raise Exception('Destination does not exist: %s' % dst_dir_path)
    
    dst_file_path = os.path.join(dst_dir_path, "%s.swift" % args.wrapper_prefix)
    
    if args.verbose:
        print 'dst_file_path:', dst_file_path
    
    args.package = None
    process_proto_file(args, proto_file_path, dst_file_path)
    
    # print 'complete.'
    
