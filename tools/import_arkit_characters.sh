#!/usr/bin/env bash
# Import Synty "Customizable 3D Characters Vol 2" assets into the project.
#
# Usage:
#   ./tools/import_synty_characters.sh <synty_source_dir>
#
# Where <synty_source_dir> is the root of the extracted Synty pack containing:
#   Models/Modular_Female_Character/, Models/Modular_Male_Character/,
#   External/Sprites/, Textures/
#
# This script:
# 1. Runs Blender conversion (Mixamo bones → UAL bones)
# 2. Copies converted GLBs into assets/characters/{gender}/
# 3. Copies sprite icons and texture atlas

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONVERT_SCRIPT="$SCRIPT_DIR/convert_synty_to_ual.py"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <synty_source_dir>"
    echo "  synty_source_dir: Root of extracted Synty Customizable 3D Characters Vol 2"
    exit 1
fi

SOURCE_DIR="$(cd "$1" && pwd)"
TEMP_DIR="$PROJECT_DIR/.synty_converted"
ASSETS_DIR="$PROJECT_DIR/assets/characters"

echo "=== Synty Character Import ==="
echo "Source: $SOURCE_DIR"
echo "Project: $PROJECT_DIR"
echo ""

# --- Step 0: Check prerequisites ---
if ! command -v blender &>/dev/null; then
    # Try macOS path
    BLENDER="/Applications/Blender.app/Contents/MacOS/Blender"
    if [ ! -x "$BLENDER" ]; then
        echo "ERROR: Blender not found. Install Blender or add to PATH."
        exit 1
    fi
else
    BLENDER="blender"
fi

echo "Using Blender: $BLENDER"

# --- Step 1: Run Blender conversion ---
echo ""
echo "=== Step 1: Converting FBX files to GLB with UAL bone names ==="

# Detect source structure: Models/Modular_Female_Character/ or FBX/Female/
MODELS_DIR=""
for candidate in "$SOURCE_DIR/Models" "$SOURCE_DIR/models"; do
    if [ -d "$candidate/Modular_Female_Character" ] || [ -d "$candidate/Modular_Male_Character" ]; then
        MODELS_DIR="$candidate"
        break
    fi
done

# Fallback: legacy FBX/Female/ structure
if [ -z "$MODELS_DIR" ]; then
    for candidate in "$SOURCE_DIR/FBX" "$SOURCE_DIR/fbx" "$SOURCE_DIR"; do
        if [ -d "$candidate/Female" ] || [ -d "$candidate/female" ]; then
            MODELS_DIR="$candidate"
            break
        fi
    done
fi

if [ -z "$MODELS_DIR" ]; then
    echo "ERROR: Cannot find Models/ or FBX/ directory in source."
    echo "Expected Models/Modular_Female_Character/ or FBX/Female/"
    exit 1
fi

echo "Models source: $MODELS_DIR"

rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

"$BLENDER" --background --python "$CONVERT_SCRIPT" -- "$MODELS_DIR" "$TEMP_DIR"

# --- Step 2: Organize converted files into project structure ---
echo ""
echo "=== Step 2: Organizing assets ==="

mkdir -p "$ASSETS_DIR/female/base"
mkdir -p "$ASSETS_DIR/female/parts"
mkdir -p "$ASSETS_DIR/male/base"
mkdir -p "$ASSETS_DIR/male/parts"
mkdir -p "$ASSETS_DIR/icons/female"
mkdir -p "$ASSETS_DIR/icons/male"
mkdir -p "$ASSETS_DIR/texture"

# Function to copy and organize parts for a gender
organize_gender() {
    local gender="$1"  # "Female" or "Male"
    local gender_lower="$(echo "$gender" | tr '[:upper:]' '[:lower:]')"

    echo "  Organizing $gender..."

    # Find the converted gender directory — Blender output mirrors source structure
    # Source: Models/Modular_Female_Character/ → Output: Modular_Female_Character/
    local src_dir=""
    for candidate in \
        "$TEMP_DIR/Modular_${gender}_Character" \
        "$TEMP_DIR/$gender" \
        "$TEMP_DIR/$(echo $gender | tr '[:lower:]' '[:upper:]')"; do
        if [ -d "$candidate" ]; then
            src_dir="$candidate"
            break
        fi
    done

    if [ -z "$src_dir" ] || [ ! -d "$src_dir" ]; then
        echo "  WARNING: No converted files found for $gender"
        return
    fi

    echo "    Found converted dir: $src_dir"

    # Copy base/modular model
    local base_file=""
    for candidate in \
        "$src_dir/Modular${gender}.glb" \
        "$src_dir/ModularFemale.glb" \
        "$src_dir/ModularMale.glb" \
        "$src_dir/Modular_${gender}.glb" \
        "$src_dir/modular_${gender_lower}.glb"; do
        if [ -f "$candidate" ]; then
            base_file="$candidate"
            break
        fi
    done

    if [ -n "$base_file" ]; then
        cp "$base_file" "$ASSETS_DIR/$gender_lower/base/modular_${gender_lower}.glb"
        echo "    Base model: $(basename "$base_file")"
    else
        echo "    WARNING: No base model found for $gender"
    fi

    # Copy part GLBs into category subdirectories
    local categories=("arms" "glasses" "hair" "hats" "head" "pants" "shoes" "torso")
    if [ "$gender_lower" = "male" ]; then
        categories+=("beard")
    fi

    for category in "${categories[@]}"; do
        mkdir -p "$ASSETS_DIR/$gender_lower/parts/$category"

        # Build search pattern — "arms" parts are named HANDS_*.fbx in source
        local search_patterns=("$category")
        if [ "$category" = "arms" ]; then
            search_patterns+=("hands")
        fi
        if [ "$category" = "hats" ]; then
            search_patterns+=("hat")
        fi

        local cat_count=0
        for pattern in "${search_patterns[@]}"; do
            while IFS= read -r f; do
                local basename="$(basename "$f")"
                cp "$f" "$ASSETS_DIR/$gender_lower/parts/$category/$basename"
                cat_count=$((cat_count + 1))
            done < <(find "$src_dir" -maxdepth 3 -iname "${pattern}_*" -name "*.glb" 2>/dev/null)
            # Also match *_{pattern}* pattern for any naming convention
            while IFS= read -r f; do
                local basename="$(basename "$f")"
                # Skip if already copied
                if [ ! -f "$ASSETS_DIR/$gender_lower/parts/$category/$basename" ]; then
                    cp "$f" "$ASSETS_DIR/$gender_lower/parts/$category/$basename"
                    cat_count=$((cat_count + 1))
                fi
            done < <(find "$src_dir" -maxdepth 3 -iname "*${pattern}*" -not -iname "combined*" -not -iname "modular*" -name "*.glb" 2>/dev/null)
        done
        if [ "$cat_count" -gt 0 ]; then
            echo "    $category: $cat_count files"
        fi
    done

    # Also copy any Combined preset models
    local combined_count=0
    mkdir -p "$ASSETS_DIR/$gender_lower/combined"
    while IFS= read -r f; do
        cp "$f" "$ASSETS_DIR/$gender_lower/combined/$(basename "$f")"
        combined_count=$((combined_count + 1))
    done < <(find "$src_dir" -maxdepth 3 -iname "*combined*" -name "*.glb" 2>/dev/null)
    if [ "$combined_count" -gt 0 ]; then
        echo "    combined: $combined_count files"
    fi

    echo "    Done organizing $gender"
}

organize_gender "Female"
organize_gender "Male"

# --- Step 3: Copy sprite icons ---
echo ""
echo "=== Step 3: Copying sprite icons ==="

SPRITES_DIR=""
for candidate in "$SOURCE_DIR/External/Sprites" "$SOURCE_DIR/Sprites" "$SOURCE_DIR/sprites"; do
    if [ -d "$candidate" ]; then
        SPRITES_DIR="$candidate"
        break
    fi
done

if [ -n "$SPRITES_DIR" ] && [ -d "$SPRITES_DIR" ]; then
    # Handle both flat layout (Female*.png) and subdirectory layout (Female_Sprites/*.png)
    female_copied=0
    male_copied=0

    # Subdirectory layout: External/Sprites/Female_Sprites/*.png
    if [ -d "$SPRITES_DIR/Female_Sprites" ]; then
        for f in "$SPRITES_DIR/Female_Sprites/"*.png; do
            [ -f "$f" ] && cp "$f" "$ASSETS_DIR/icons/female/" && female_copied=$((female_copied + 1))
        done
    fi
    if [ -d "$SPRITES_DIR/Male_Sprites" ]; then
        for f in "$SPRITES_DIR/Male_Sprites/"*.png; do
            [ -f "$f" ] && cp "$f" "$ASSETS_DIR/icons/male/" && male_copied=$((male_copied + 1))
        done
    fi

    # Flat layout fallback: Female*.png / Male*.png at sprites root
    if [ "$female_copied" -eq 0 ]; then
        for f in "$SPRITES_DIR"/Female*.png "$SPRITES_DIR"/female*.png; do
            [ -f "$f" ] && cp "$f" "$ASSETS_DIR/icons/female/" && female_copied=$((female_copied + 1))
        done
    fi
    if [ "$male_copied" -eq 0 ]; then
        for f in "$SPRITES_DIR"/Male*.png "$SPRITES_DIR"/male*.png; do
            [ -f "$f" ] && cp "$f" "$ASSETS_DIR/icons/male/" && male_copied=$((male_copied + 1))
        done
    fi

    echo "  Female sprites: $female_copied"
    echo "  Male sprites: $male_copied"
else
    echo "  WARNING: No Sprites directory found, skipping icons"
fi

# --- Step 4: Copy texture atlas ---
echo ""
echo "=== Step 4: Copying texture atlas ==="

TEXTURE_FILE=""
for candidate in \
    "$SOURCE_DIR/Textures/Texture_Modular_Characters.png" \
    "$SOURCE_DIR/textures/Texture_Modular_Characters.png" \
    "$SOURCE_DIR/Texture_Modular_Characters.png"; do
    if [ -f "$candidate" ]; then
        TEXTURE_FILE="$candidate"
        break
    fi
done

if [ -n "$TEXTURE_FILE" ]; then
    cp "$TEXTURE_FILE" "$ASSETS_DIR/texture/Texture_Modular_Characters.png"
    echo "  Texture atlas copied"
else
    echo "  WARNING: Texture atlas not found, skipping"
fi

# --- Step 5: Cleanup ---
echo ""
echo "=== Step 5: Cleanup ==="
rm -rf "$TEMP_DIR"
echo "  Temporary files removed"

# --- Summary ---
echo ""
echo "=== Import Complete ==="
echo "Assets directory: $ASSETS_DIR"
echo ""
echo "Structure:"
find "$ASSETS_DIR" -type d | sort | sed "s|$ASSETS_DIR|assets/characters|" | while read -r d; do
    count=$(find "$ASSETS_DIR/${d#assets/characters}" -maxdepth 1 \( -name "*.glb" -o -name "*.png" \) 2>/dev/null | wc -l | tr -d ' ')
    if [ "$count" -gt 0 ]; then
        echo "  $d/ ($count files)"
    else
        echo "  $d/"
    fi
done

echo ""
echo "Next steps:"
echo "  1. Open project in Godot to trigger .import for GLB files"
echo "  2. Run validation: Mechanical Turk --path . --script tools/validate_synty_parts.gd"
echo "  3. Check warnings in Blender output above for unmapped bones"
