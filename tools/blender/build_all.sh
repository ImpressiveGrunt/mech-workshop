#!/usr/bin/env bash
# Rebuild every game asset with Blender (models, data/parts.json, previews).
#   tools/blender/build_all.sh            # full build with preview renders
#   SKIP_RENDER=1 tools/blender/build_all.sh   # models only (fast)
set -euo pipefail
cd "$(dirname "$0")/../.."
BLENDER=${BLENDER:-blender}
for script in build_mech.py build_workshop.py; do   # environments get added one at a time
  echo "== $script"
  "$BLENDER" -b --factory-startup --python "tools/blender/$script" 2>&1 \
    | grep -E "EXPORTED|RENDERED|SAVED|WROTE|Error|Traceback" || true
done
