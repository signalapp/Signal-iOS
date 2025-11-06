cmake_minimum_required(VERSION 3.22.1)
project(EMMA_SecurityKit)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -Wextra -fexceptions -frtti")

# iOS-specific settings
set(CMAKE_OSX_DEPLOYMENT_TARGET "15.0")
set(CMAKE_OSX_ARCHITECTURES "arm64")

# Platform detection
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(IOS TRUE)
    add_definitions(-DIOS_PLATFORM)
endif()

# Source files
set(COMMON_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/Common/ios_platform.cpp
)

set(SECURITY_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/SecurityKit/Native/el2_detector.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/SecurityKit/Native/performance_counters.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/SecurityKit/Native/cache_operations.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/SecurityKit/Native/memory_scrambler.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/SecurityKit/Native/timing_obfuscation.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/SecurityKit/Native/nist_pqc.cpp
)

set(SECURITY_BRIDGE_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/SecurityKit/Bridge/EMSecurityKit.mm
)

# Create static library for SecurityKit
add_library(EMMASecurityKit STATIC
    ${COMMON_SOURCES}
    ${SECURITY_SOURCES}
    ${SECURITY_BRIDGE_SOURCES}
)

# Include directories
target_include_directories(EMMASecurityKit PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/Common
    ${CMAKE_CURRENT_SOURCE_DIR}/SecurityKit/Native
    ${CMAKE_CURRENT_SOURCE_DIR}/SecurityKit/Bridge
)

# Link iOS frameworks
if(IOS)
    find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)
    find_library(SECURITY_FRAMEWORK Security REQUIRED)

    target_link_libraries(EMMASecurityKit
        ${FOUNDATION_FRAMEWORK}
        ${SECURITY_FRAMEWORK}
    )
endif()

# Installation
install(TARGETS EMMASecurityKit
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    FRAMEWORK DESTINATION Frameworks
)

# Install headers
install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/SecurityKit/Bridge/
    DESTINATION include/EMMASecurityKit
    FILES_MATCHING PATTERN "*.h"
)
