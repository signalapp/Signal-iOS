#!/bin/bash
#
# Rebrand EMMA to SWORDCOMM across entire codebase
#

set -e

echo "Rebranding EMMA to SWORDCOMM..."

# Find all text files
FILES=$(find SWORDCOMM -type f \( \
    -name "*.md" -o \
    -name "*.swift" -o \
    -name "*.h" -o \
    -name "*.cpp" -o \
    -name "*.sh" -o \
    -name "*.py" -o \
    -name "*.txt" -o \
    -name "*.cmake" -o \
    -name "CMakeLists.txt" -o \
    -name "*.podspec" \
\))

COUNT=0

for file in $FILES; do
    # Skip if file doesn't exist (in case of spaces in names)
    [ -f "$file" ] || continue

    # Create temp file
    temp_file="${file}.tmp"

    # Perform replacements
    sed -e 's/EMMASecurityKit/SWORDCOMMSecurityKit/g' \
        -e 's/EMMATranslationKit/SWORDCOMMTranslationKit/g' \
        -e 's/EMMAInitializer/SWORDCOMMInitializer/g' \
        -e 's/EMMASettings/SWORDCOMMSettings/g' \
        -e 's/EMMAMessage/SWORDCOMMMessage/g' \
        -e 's/EMMA-Bridging/SWORDCOMM-Bridging/g' \
        -e 's/EMMA\//SWORDCOMM\//g' \
        -e 's/\bEMMA /SWORDCOMM /g' \
        -e 's/\(EMMA\)/SWORDCOMM/g' \
        -e 's/\[EMMA\]/[SWORDCOMM]/g' \
        -e 's/"EMMA/"SWORDCOMM/g' \
        -e 's/EMMA:/SWORDCOMM:/g' \
        -e 's/# EMMA/# SWORDCOMM/g' \
        -e 's/\* EMMA/\* SWORDCOMM/g' \
        -e 's/EMMA Integration/SWORDCOMM Integration/g' \
        -e 's/EMMA iOS Port/SWORDCOMM iOS Port/g' \
        -e 's/EMMA Security/SWORDCOMM Security/g' \
        -e 's/EMMA Translation/SWORDCOMM Translation/g' \
        -e 's/EMMA Phase/SWORDCOMM Phase/g' \
        -e 's/Enterprise Messaging Military-grade Android/Secure Worldwide Operations & Real-time Data Communication/g' \
        -e 's/emma\./swordcomm\./g' \
        -e 's/\.emma/.swordcomm/g' \
        "$file" > "$temp_file"

    # Replace original file if changes were made
    if ! cmp -s "$file" "$temp_file"; then
        mv "$temp_file" "$file"
        COUNT=$((COUNT + 1))
        echo "  Updated: $file"
    else
        rm "$temp_file"
    fi
done

echo ""
echo "Rebranding complete!"
echo "Updated $COUNT files"
