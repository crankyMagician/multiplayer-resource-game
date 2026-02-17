# Friend & Party System

## Overview

Server-authoritative player-to-player social system. Managed by `FriendManager` (`scripts/world/friend_manager.gd`), a child node of GameWorld with no `class_name` (follows SocialManager/QuestManager pattern).

All mutations go through the server. Clients never modify social state directly.

## Architecture

### Data Model

Social data lives in the server's `player_data_store`:

```
player_data_store[peer_id]["social"] = {
    "friends": [player_id, ...],            # Array of UUID strings
    "blocked": [player_id, ...],            # Array of UUID strings
    "incoming_requests": [                   # Array of request dicts
        {"from_id": uuid, "from_name": str, "sent_at": float}
    ],
    "outgoing_requests": [                   # Array of request dicts
        {"to_id": uuid, "to_name": str, "sent_at": float}
    ]
}
```

Party data is runtime-only (NOT persisted):

```
FriendManager.parties = {
    party_id: {
        "party_id": int,
        "leader_id": player_uuid,
        "members": [player_uuid, ...],
        "invites": {player_uuid: {"invited_at": float}}
    }
}
FriendManager.player_party_map = {player_uuid: party_id}
```

### Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `MAX_PENDING_REQUESTS` | 20 | Max outgoing friend requests |
| `MAX_FRIENDS` | 100 | Max friends per player |
| `MAX_BLOCKED` | 50 | Max blocked players |
| `PARTY_INVITE_TTL_SEC` | 60 | Invite auto-expires after 60s |
| `MAX_PARTY_SIZE` | 4 | Max party members |

### Concurrency: Pair-Locks

Friend mutations use pair-locks to prevent race conditions when two players interact simultaneously:

```gdscript
_pair_key(a, b) -> String  # Deterministic "a:b" or "b:a" (alphabetical)
_acquire_lock(key) -> bool  # Returns false if already locked
_release_lock(key)          # Must be called after mutation completes
```

## Friend Request Flow

### Send Request

1. Client calls `request_send_friend_request.rpc_id(1, target_name)`
2. Server validates: not self, not blocked, not already friends, no duplicate request, under pending cap
3. **Online target**: Direct `_process_friend_request()` — updates both players' data stores, sends RPCs
4. **Offline target**: `SaveManager.load_player_async()` → signal → resolve player_id → `PATCH /api/players/:id/social` for atomic MongoDB mutation
5. **Cross-request auto-accept**: If Bob already has an outgoing request to Alice, and Alice sends one to Bob, auto-accepts (calls `_do_accept_friend`)

### Accept Request

1. Client calls `request_accept_friend_request.rpc_id(1, from_player_id)`
2. Server acquires pair-lock, adds to both friends lists, removes requests from both sides
3. If requester is online: direct data store update + `_notify_friend_added` RPC
4. If requester is offline: `PATCH /api/players/:id/social` (`$addToSet` friend, `$pull` outgoing request)

### Decline / Cancel

- `request_decline_friend_request(from_player_id)` — removes incoming request from self + outgoing from sender
- `request_cancel_friend_request(to_player_id)` — removes outgoing request from self + incoming from target
- Both handle online + offline targets

### Remove Friend

- `request_remove_friend(player_id)` — removes from both players' friends lists, handles online + offline

## Blocking

`request_block_player(target_name)` → `_process_block()`:

1. Adds target to sender's `blocked` list
2. Removes existing friendship (both sides)
3. Removes all pending requests (both directions)
4. Auto-kicks blocked player from any shared party (`_kick_from_shared_party`)
5. Saves both players (online or offline patch)

**Block prevents**: friend requests, party invites, gift items. Checked in both directions (blocker and blocked).

**Unblock**: `request_unblock_player(player_id)` — removes from blocked list. Does NOT restore friendship.

## Party System

### Create Party

`request_create_party.rpc_id(1)`:
- Player must not already be in a party
- Creates party with creator as leader and sole member
- Assigns auto-incrementing `_next_party_id`

### Invite to Party

`request_invite_to_party.rpc_id(1, target_player_id)`:
- Only party leader can invite
- Target must be a friend (checked via leader's friends list)
- Target must not be blocked (either direction)
- Target must not already be in a party
- Party must not be full (< MAX_PARTY_SIZE)
- Creates invite with `invited_at` timestamp, sends `_notify_party_invite` RPC to target

### Accept Invite

`request_accept_party_invite.rpc_id(1, party_id)`:
- Validates invite exists and hasn't expired (60s TTL)
- Adds player to party members, removes invite
- Syncs party state to all members via `_sync_party_to_all`

### Leave / Kick / Disband

- **Leave**: `request_leave_party.rpc_id(1)` — removes self. If leader leaves, transfers to oldest remaining member.
- **Kick**: `request_kick_from_party.rpc_id(1, target_player_id)` — leader-only. Removes target from party.
- **Auto-disband**: Party disbanded when last member leaves or is removed.

### Disconnect Handling

`handle_disconnect(peer_id)`:
1. Gets player's `player_id` from data store
2. Removes from party members
3. Cleans up any pending invites to this player
4. If leader disconnected: transfers leadership to oldest remaining member, syncs via `_sync_party_to_all`
5. If party is now empty: disbands (erases from `parties`)

## RPCs Reference

### Client → Server

| RPC | Parameters | Purpose |
|-----|-----------|---------|
| `request_send_friend_request` | `target_name: String` | Send friend request by name |
| `request_accept_friend_request` | `from_player_id: String` | Accept incoming request |
| `request_decline_friend_request` | `from_player_id: String` | Decline incoming request |
| `request_cancel_friend_request` | `to_player_id: String` | Cancel outgoing request |
| `request_remove_friend` | `player_id: String` | Remove existing friend |
| `request_block_player` | `target_name: String` | Block a player |
| `request_unblock_player` | `player_id: String` | Unblock a player |
| `request_create_party` | *(none)* | Create new party |
| `request_invite_to_party` | `target_player_id: String` | Invite friend to party |
| `request_accept_party_invite` | `party_id: int` | Accept party invite |
| `request_decline_party_invite` | `party_id: int` | Decline party invite |
| `request_leave_party` | *(none)* | Leave current party |
| `request_kick_from_party` | `target_player_id: String` | Kick member (leader only) |

### Server → Client

| RPC | Parameters | Purpose |
|-----|-----------|---------|
| `_friend_action_result` | `action, success, message` | Result feedback for any action |
| `_notify_friend_request` | `from_name, from_id` | New incoming request notification |
| `_notify_friend_added` | `name, player_id` | Friend accepted notification |
| `_notify_friend_removed` | `player_id` | Friend removed notification |
| `_sync_friends_list` | `friends, blocked, incoming, outgoing` | Full social state sync |
| `_sync_party_state` | `party_id, leader_id, members_json, msg` | Full party state sync |
| `_notify_party_invite` | `party_id, leader_name` | Party invite notification |

## Client-Side (PlayerData + UI)

### PlayerData Autoload

Social state mirrored on client:
- `PlayerData.friends_list: Array` — friend UUIDs
- `PlayerData.blocked_list: Array` — blocked UUIDs
- `PlayerData.incoming_friend_requests: Array` — request dicts
- `PlayerData.outgoing_friend_requests: Array` — request dicts
- `PlayerData.group_party_id: int` — current party ID (-1 if none)
- `PlayerData.group_party_leader_id: String` — leader UUID
- `PlayerData.group_party_members: Array` — member UUIDs

Signals: `player_friends_changed`, `player_party_updated`

### FriendListUI

- `scenes/ui/friend_list_ui.tscn` + `scripts/ui/friend_list_ui.gd`
- F key to toggle (CanvasLayer, layer 10)
- Tabs: Friends, Requests (incoming/outgoing), Blocked
- Actions: Accept/Decline requests, Remove friends, Block/Unblock, Create/Invite/Leave party

## Offline Player Social Mutations

When a target player is offline, mutations use the Express API:

```
PATCH /api/players/:player_id/social
Body: { "add_friend": uuid, "remove_friend": uuid, "add_incoming_request": {...}, ... }
```

Operations: `add_friend`, `remove_friend`, `add_incoming_request`, `remove_incoming_request_from`, `add_outgoing_request`, `remove_outgoing_request_to`, `add_blocked`, `remove_blocked`

MongoDB uses `$addToSet` / `$pull` for atomic array operations.

## Known Issues & Gotchas

- **Legacy saves without `player_id`**: File I/O mode generates UUIDs for new players, but saves created before the UUID system lack `player_id`. The join flow's `_finalize_join()` does NOT backfill missing `player_id` — only creature IDs, IVs, and bond data are backfilled. FriendManager requires valid `player_id` UUIDs for all operations. API-connected deployments are unaffected (API always generates UUIDs).
- **Pair-lock not released on early return**: If a method acquires a lock but returns early due to validation failure before releasing it, that pair stays locked until server restart. Current code releases in all paths.
- **Party state not persisted**: If the server restarts, all parties are lost. This is by design — parties are session-level groupings.

## MCP Integration Testing

See `docs/mcp-testing.md` § "Friend & Party System Testing" for the full MCP runtime test procedure, including direct method calls that bypass `get_remote_sender_id()`.

### Quick Reference — Direct Server Method Calls

These bypass RPC entry points (which use `get_remote_sender_id()` and freeze MCP injection):

```gdscript
# Get FriendManager reference
var fm = get_tree().root.get_node("Main/GameWorld/FriendManager")

# Send friend request (Alice → Bob)
fm._process_friend_request(alice_peer, alice_uuid, "Alice", bob_peer, bob_uuid, "Bob")

# Accept friend request (Bob accepts Alice)
fm._do_accept_friend(bob_peer, bob_uuid, "Bob", alice_peer, alice_uuid, "Alice")

# Block player
fm._process_block(alice_peer, alice_uuid, bob_peer, bob_uuid, "Bob")

# Disconnect handling
fm.handle_disconnect(bob_peer)

# Sync party state to all members
fm._sync_party_to_all(party_id)
```

### Retrieving Peer/Player IDs

```gdscript
var nm = get_tree().root.get_node("NetworkManager")
for pid in nm.player_data_store:
	var name = str(nm.player_data_store[pid].get("player_name", ""))
	var uuid = str(nm.player_data_store[pid].get("player_id", ""))
	# Use pid (peer_id) and uuid (player_id) in subsequent calls
```
