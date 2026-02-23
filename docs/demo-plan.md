# Demo Plan: Cast Iron Cove

This is the target demo plan we are building toward. The status list below tracks what is already implemented versus what remains.

## Status (Cross-Check)

### Done (Implemented Today)
- Battle system with wild, trainer, and PvP modes (61 Munchies, 57 moves, 20 abilities).
- Crafting system with Kitchen, Workbench, and Cauldron stations (67 recipes).
- Farming actions and tool upgrades (plant, water, harvest, till).
- NPC dialogue, gifting, and friendship tiers (5 NPCs currently implemented).
- Quest system (6 quests: 3 main story, 1 side, 1 daily, 1 weekly).
- Shops and trading (3 shops, P2P trade, NPC creature trades).
- Restaurant interiors with farm plots and enter/exit flow.
- Weather and calendar system (day cycle, seasonal calendar, rain auto-watering).
- Compendium and stats tracking.
- Excursion system expanded to 160x160 procedural arenas with Synty 3D models, cliff boundaries, path navigation, season-themed vegetation, and rare grove ruins.
- Poacher trainer NPCs in excursions: 3-5 hostile trainers per instance with difficulty scaling by distance, dynamic team composition, and shared party rewards.
- Multiple excursion zone types with themed biomes: Coastal Wreckage (pirate/beach), Fungal Hollow (dark caves), Volcanic Crest (scorched desert), Frozen Pantry (snow/ice), plus default seasonal wilds.
- 5 excursion portals spread across Cast Iron Cove with zone-specific visuals, glow colors, encounter tables, terrain tinting, and ambient lighting.

### To Do (Target for Demo)
- Train arrival intro and letter UI sequence.
- Full Cast Iron Cove town layout with districts and environmental storytelling.
- Expanded NPC roster and schedules (beyond current 5 NPCs).
- Restaurant service loop: customers, menu planning, reputation, and upgrades.
- Cooking and preparation mini-games.
- Festival system, weekly events, and community potlucks.
- Expanded biomes and encounter tables (target 18 biomes).
- Expanded content targets (200+ Munchies, 200+ recipes, 150+ ingredients).
- Additional exploration systems (tide mechanics, fog events, beach combing, fishing).

### Current Build Mapping (Reference)
- Implemented NPCs: Baker Brioche, Sage Herbalist, Old Salt, Ember Smith, Professor Umami.
- Implemented encounter zones: Herb Garden, Flame Kitchen, Frost Pantry, Harvest Field, Sour Springs, Fusion Kitchen.
- Implemented excursion portals: The Wilds (-8,0,-25), Coastal Wreckage (-33,0,-12), Fungal Hollow (8,0,-68), Volcanic Crest (45,0,-12), Frozen Pantry (15,0,38). Each with zone-specific terrain, encounter tables, poacher trainers, and 15-minute timer.
- Starter Munchie: Rice Ball (Grain).
- Restaurant is an instanced interior plus farm plots; no customer service loop yet.

### Implemented Munchies (61)

| # | Name | Types |
|---|------|-------|
| 1 | Banana Split | Tropical, Sweet |
| 2 | Basil Sprite | Herbal |
| 3 | Beet Boxer | Earthy |
| 4 | Blaze Wyvern | Spicy |
| 5 | Butter Sprite | Dairy, Sweet |
| 6 | Cheese Golem | Dairy |
| 7 | Chili Drake | Spicy |
| 8 | Cinnamon Swirl | Spicy, Aromatic |
| 9 | Citrus Fiend | Sour, Spicy |
| 10 | Cocoa Imp | Bitter, Sweet |
| 11 | Coconut Crab | Tropical, Mineral |
| 12 | Coffee Golem | Bitter, Earthy |
| 13 | Crab Knight | Liquid, Mineral |
| 14 | Cream Elemental | Dairy, Sweet |
| 15 | Dragon Wok | Spicy, Mineral |
| 16 | Drumstick Warrior | Protein |
| 17 | Ferment Lord | Toxic, Earthy |
| 18 | Frost Berry | Sweet |
| 19 | Ginger Snap | Spicy |
| 20 | Hemlock Shade | Toxic |
| 21 | Herb Guardian | Herbal, Grain |
| 22 | Iron Pot | Mineral, Grain |
| 23 | Jellyfish Drift | Liquid, Toxic |
| 24 | Kraken Broth | Liquid, Umami |
| 25 | Lavender Moth | Aromatic |
| 26 | Lemon Imp | Sour |
| 27 | Lobster Lord | Liquid, Mineral |
| 28 | Mango Parrot | Tropical, Aromatic |
| 29 | Mint Wisp | Herbal, Sweet |
| 30 | Moonlight Souffle | Sweet, Aromatic |
| 31 | Mushroom Cap | Umami |
| 32 | Mushroom Monarch | Earthy, Toxic |
| 33 | Obsidian Chef | Mineral, Spicy |
| 34 | Onigiri Knight | Grain |
| 35 | Oyster Sage | Liquid, Mineral |
| 36 | Pickle Toad | Sour, Herbal |
| 37 | Pineapple Knight | Tropical, Sour |
| 38 | Potato Brute | Earthy, Grain |
| 39 | Pumpkin Guard | Grain, Umami |
| 40 | Rice Ball | Grain |
| 41 | Rosemary Elk | Aromatic, Herbal |
| 42 | Saffron Spirit | Spicy, Aromatic |
| 43 | Salt Crystal | Mineral |
| 44 | Sear Slug | Spicy, Umami |
| 45 | Shrimp Scout | Liquid |
| 46 | Sorbet Phoenix | Sweet, Spicy |
| 47 | Sourdough Sentinel | Sour, Grain |
| 48 | Squid Mystic | Liquid |
| 49 | Steak Beast | Protein |
| 50 | Sushi Samurai | Grain, Umami |
| 51 | Taffy Serpent | Sweet, Sour |
| 52 | Tempeh Titan | Protein, Earthy |
| 53 | Tofu Block | Umami, Herbal |
| 54 | Tofu Sage | Protein |
| 55 | Truffle Burrower | Earthy |
| 56 | Truffle King | Umami |
| 57 | Turmeric Titan | Spicy, Earthy |
| 58 | Vanilla Fairy | Aromatic, Sweet |
| 59 | Wasabi Viper | Toxic, Spicy |
| 60 | Wheat Golem | Grain |
| 61 | Yogurt Wisp | Dairy |

## Core Concept
Pokemon meets Stardew Valley through cooking. You inherit your eccentric Great-Aunt Cordelia's quirky restaurant and overgrown garden after she mysteriously disappears, leaving only a cryptic note about "settling an old debt." Master her unconventional Munchie-care methods, restore her farm-to-table empire, and follow recipe clues to discover her fate.

## What We Have Established

### Setting
- Cast Iron Cove: A cozy, coastal valley once known for rich soils, vibrant ingredients, and culinary tourism.
- You inherit Aunt Cordelia's restaurant (known locally as "that weird place") and a neglected garden.
- Cordelia vanished three months ago with her favorite Munchie team.
- Restaurant needs restoration, garden needs clearing and replanting.

### Aunt Cordelia's Legacy
- World-renowned chef who treated her cooked Munchies like beloved pets.
- Locals saw her as eccentric, but admitted her food was incredible.
- Her methods worked: pampered Munchies were unusually strong and loyal.
- Left behind cryptic recipes and growing techniques.

### Cast Iron Cove Details
- The magic: Built on a "flavor leyline" that enhances the bond between ingredients and emotion.
- The community: Faded seaside tourist town, now quieter with farmers, fisherfolk, and retired chefs.
- The vibe: Northern California coastal energy, quirky and artsy with a touch of mystery.
- Munchie culture: Locals always lived alongside Munchies, but Cordelia's "pet care" methods were seen as extreme.

### Your Restaurant
- Location: Edge of town, near cliffs and beach, scenic but isolated.
- Condition: Functional but neglected, kitchen barely works, garden overgrown.
- Architecture: Converted coastal greenhouse with big windows, rusted wrought iron arches, sea-worn wooden beams.

## Core Gameplay (Target)
- Farm-to-table emphasis, growing is crucial.
- 18 biomes to explore, 18 Munchie types to master.
- Restaurant progression from local oddity to respected establishment.
- Master chef challenges unlock new areas and techniques.
- Seasonal festivals and relationship building.

## Player Goals (Target)
- Main: Find Aunt Cordelia by decoding her recipe clues.
- Collection: 200+ recipes, 150+ ingredients, 200+ Munchies.
- Progression: Transform reputation and master cooking techniques.
- Social: Befriend NPCs and prove Cordelia's methods work.

## Cast Iron Cove Town: Key NPCs and Layout (Target)

### Core Cast (Priority for Demo)
- Mayor Rosemary Hartwell: Town leader and quest giver.
- Captain Sal "The Salted" Haddock: Fisherman and seafood supplier.
- Pepper Santos: Hot sauce artisan and Spicy Munchie expert.
- Old Sage Murphy: Herb garden keeper and advanced grower.
- Hubert Crumb: Local baker and Sweet Munchie specialist.

### Expanded NPC Roster (Target)
- Hazel Mapleton: General Store.
- Clay Brennan: Potter and dishware maker.
- Innkeeper Mabel: Tide's End Inn.
- Scarlet Winters: Tailor.
- Professor Quill: Book shop and lore.
- Iris Greenthumb: Garden shop and seed specialist.
- Dr. Honey: Clinic and Munchie care.
- Future romance options: Clementine Smith, River Song, Alex Hartwell.

## Starter Biomes for Demo (Target)
These are the hand-crafted overworld encounter zones — fixed areas in Cast Iron Cove where wild Munchies roam. Distinct from the procedural excursion portals below.

- Fermented Hollow: Toxic, Umami, Spoiled, Earthy.
- Blackened Crest: Spicy, Protein, Mineral.
- Battered Bay: Liquid, Sweet, Aromatic.
- Salted Shipwreck: Spoiled, Toxic, Bitter.

## Excursion Portals (Implemented)
Five excursion portals are spread across Cast Iron Cove, each leading to a procedurally generated 160x160 arena with zone-themed terrain, vegetation, encounter tables, and poacher trainers. Excursions are party-gated (requires a party to enter), instanced per-party, and run on a 15-minute timer. All loot is shared among party members.

| Portal | Map Location | Theme | Key Creatures |
|--------|-------------|-------|---------------|
| The Wilds | North of town (-8, 0, -25) | Seasonal grassland/forest | Herb Guardian, Blaze Wyvern, Citrus Fiend |
| Coastal Wreckage | West cliffs (-33, 0, -12) | Pirate shipwrecks, tropical beach | Shrimp Scout, Jellyfish Drift, Squid Mystic |
| Fungal Hollow | Deep north (8, 0, -68) | Dark caves, giant mushrooms | Mushroom Cap, Truffle Burrower, Ferment Lord |
| Volcanic Crest | East, past farm (45, 0, -12) | Scorched desert, cacti, lava | Ginger Snap, Dragon Wok, Obsidian Chef |
| Frozen Pantry | South of spawn (15, 0, 38) | Snow pines, ice, knight ruins | Crab Knight, Oyster Sage, Kraken Broth |

Each zone has common and rare encounter tables, a rare grove with ruins, 3-5 poacher trainers with difficulty scaling by distance from spawn, and zone-specific decorations and ambient lighting.

## Starting Area and Demo Design (Target)

### Arrival: The Coastal Express
- Opening sequence shows the coastline and Cordelia's letter.
- Cast Iron Cove appears as the train rounds the final bend.

### Station Platform (Tutorial Start)
- Emotional grounding and basic controls.
- Wild herb-type Munchie nibbles by the tracks.
- Station master garden introduces farming potential.
- Letter reading triggers memories of Cordelia.

### Harbor Square (Town Center)
- Social hub and quest introduction.
- Town Hall with quest board and Munchie registry.
- Hubert's Bakery as the first creation tutorial.
- Market stalls and wandering Munchies establish town life.

### The Salty Ladle Path (Restaurant Approach)
- Overgrown path and festival posters build anticipation.
- First battle encounter in the garden shed.

### The Restaurant and Garden
- Kitchen functional but neglected.
- Dining room dusty, furniture covered.
- Garden plots overgrown, greenhouse intact but needs repair.
- Progressive restoration: clear weeds, repair equipment, open dining room.

### Tidewater Beach (First Exploration Zone)
- Crab-like Munchies, diving flyers, and burrowing types.
- Ingredient drops: beach glass, salt crystals, kelp strands, pearl fragments.

## Complete Town Layout (Target)

### District 1: Harbor Heights (Upper Town)
- The Salty Ladle (your restaurant).
- Cordelia's Cottage (your living quarters).
- Murphy's Hillside Garden (locked early).
- Overlook Park (sunset gathering spot).
- **The Wilds portal** — excursion entrance north of town, glowing purple at the tree line.

### District 2: Town Square (Central Hub)
- Town Hall (quest board, registry, calendar).
- Hubert's Bakery (creation tutorial).
- Harbor Square Fountain (meeting point).
- Pepper's Spice Emporium (spice challenges).
- Cove General Store (basic tools and seeds).
- The Cracked Pot (pottery and dishware).

### District 3: Wharf Walk (Waterfront)
- Tide's End Inn (travelers, rooms, stories).
- Haddock's Fishing Dock (fishing mini-game).
- Lighthouse (locked future content).
- Beach access path and driftwood scavenging.
- Old Warehouse (optional dungeon).
- **Coastal Wreckage portal** — excursion entrance on the west cliffs, visible from the docks.

### District 4: Market Row (Shopping Street)
- Threads and Needles (clothing and uniforms).
- The Book Nook (recipes and lore).
- Bloom and Grow Garden Center (advanced seeds).
- Dr. Honey's Clinic (Munchie care).

### Outskirts Landmarks
- **Volcanic Crest portal** — east of the farm zone, a shimmering orange gateway amid scorched earth.
- **Frozen Pantry portal** — south of the spawn point, an icy blue archway flanked by snow pines.
- **Fungal Hollow portal** — deep north past the trainer gauntlet, a dim purple rift among giant mushrooms.

## Demo Flow (Target 30-40 Minutes)

### Act 1: Arrival and Discovery (0-10 min)
1. Train arrival and letter reading.
2. Walk to town and first Munchie sightings.
3. Mayor meeting and town introduction.
4. First look at the restaurant and garden.
5. Cottage settling and save tutorial.

### Act 2: Learning the Ropes (10-20 min)
1. Garden shed battle tutorial.
2. Meet Hubert Crumb for creation tutorial.
3. Create first Munchie (crafting system).
4. Plant first seeds (farming basics).
5. Cook first dish (cooking tutorial).
6. Meet shopkeepers (economy introduction).
7. Discover The Wilds portal while exploring north — it glows invitingly but requires a party to enter, motivating the player to make friends.

### Act 3: Community Integration (20-30 min)
1. Morning routine: water plants and collect yields.
2. Complete three town quests.
3. Pepper's spice challenge mini-game.
4. Beach exploration and combat practice.
5. Form a party and complete first excursion in The Wilds — shared loot introduces cooperative play; poacher trainers provide mid-game combat challenge.
6. First lunch service (restaurant gameplay).
7. Evening socializing and gift giving.

### Act 4: Mystery Hooks (30-40 min)
1. Find Cordelia's journal — it references a rare ingredient (Mystic Herb) found only in a specific excursion zone, sending the player to Coastal Wreckage or Fungal Hollow.
2. Murphy's cryptic hint.
3. Lighthouse mystery tease.
4. Excursion expedition to the journal's target zone — ties the mystery to excursion exploration.
5. Tournament letter arrives.
6. Captain's revelation.
7. Demo end celebration.

## Activities and Mini-Games (Target)
- Spice tolerance challenge (rhythm).
- Fishing mini-game (timing).
- Speed chopping (prep time attack).
- Munchie racing on the beach.
- Memory recipe mini-game.
- Garden planning puzzle.
- Merchant haggling.

## Environmental and Atmospheric Details (Target)

### Time of Day
- Morning: Mist off the ocean, shops open.
- Noon: Busy town, wild Munchies seek shade.
- Evening: Golden hour and social time.
- Night: Lanterns and nocturnal creatures.

### Weather
- Clear: Standard spawns and growth.
- Rain: Increased plant growth, water-type Munchies more active.
- Fog: Rare Munchies appear, visibility reduced.
- Storm: Indoor focus and relationship scenes.

### Seasonal Touches
- Beach roses in summer areas.
- Driftwood arrangements change monthly.
- Seasonal Munchie migrations.
- Calendar teases upcoming festivals.

## Technical Implementation Areas (Target)
- Munchie creation system.
- Battle and loot system.
- Restaurant management and customers.
- Garden and farming system.
- Social and quest system.
- Environmental systems (day/night, weather, tide).

## UI and UX Needs (Target)
- Cozy, hand-drawn UI elements.
- Recipe book interface.
- Munchie team management screen.
- Garden planner overlay.
- Restaurant customization mode.

## Save System Requirements (Target)
- Restaurant state persistence.
- Garden plot data.
- Munchie team and storage.
- NPC relationship values.
- Quest progress tracking.
- Unlocked recipes and areas.

## Demo Success Metrics
Players should:
- Feel emotional connection to Cordelia's legacy.
- Understand the core loop: Battle -> Collect -> Create -> Cook.
- Want to explore beyond the cove.
- Create 2-3 Munchies and serve 5+ dishes.
- Be curious about Cordelia's disappearance.
- Feel the cozy, welcoming atmosphere.

## Demo Ending Hook
A letter arrives from the Culinary Council in Whispering Woods, mentioning Cordelia registered for their Master Chef Tournament but never arrived. To investigate, you will need to prove your worth by earning reputation stars.

## Terminology Note
This document uses the player-facing term Munchies. Code and data use "creature" and "creature_id".

## Approval
Reviewed and approved 7/27 by Heather Sandfort, Chief Munchie Biologist, FNP. Theme is set.
