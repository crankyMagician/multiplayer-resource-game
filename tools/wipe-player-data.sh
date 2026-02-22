#!/bin/bash
# Wipe all player data (local + deployed MongoDB)
# Usage: ./tools/wipe-player-data.sh [--remote-only | --local-only]

set -e

REMOTE_ONLY=false
LOCAL_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --remote-only) REMOTE_ONLY=true ;;
    --local-only) LOCAL_ONLY=true ;;
    -h|--help)
      echo "Usage: $0 [--remote-only | --local-only]"
      echo "  --remote-only   Only wipe deployed MongoDB data"
      echo "  --local-only    Only wipe local save files"
      echo "  (no flags)      Wipe both"
      exit 0
      ;;
  esac
done

# Local save data
if [ "$REMOTE_ONLY" = false ]; then
  LOCAL_SAVE="$HOME/Library/Application Support/Mechanical Turk/app_userdata/Creature Crafting Demo/save"
  if [ -d "$LOCAL_SAVE" ]; then
    rm -rf "$LOCAL_SAVE"
    echo "[local] Deleted save data at: $LOCAL_SAVE"
  else
    echo "[local] No save data found at: $LOCAL_SAVE"
  fi
fi

# Deployed MongoDB
if [ "$LOCAL_ONLY" = false ]; then
  SERVER="jayhawk@10.225.0.153"
  echo "[remote] Connecting to $SERVER..."
  ssh "$SERVER" "
    POD=\$(kubectl get pods -n godot-multiplayer -l app=creature-crafting-mongodb -o jsonpath='{.items[0].metadata.name}')
    echo \"[remote] MongoDB pod: \$POD\"
    kubectl exec \$POD -n godot-multiplayer -- mongo creature_crafting --quiet --eval 'var r = db.players.deleteMany({}); print(\"Deleted \" + r.deletedCount + \" player(s)\")'
    COUNT=\$(kubectl exec \$POD -n godot-multiplayer -- mongo creature_crafting --quiet --eval 'print(db.players.count())')
    echo \"[remote] Players remaining: \$COUNT\"
  "
fi

echo "Done."
