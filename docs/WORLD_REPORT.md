# Mika World 2.0 — measured world report

Every number below is produced by the in-engine test tools (`--worldtour`, `tools/mock_brain.py`) on this laptop (Intel Raptor Lake-P iGPU, Vulkan/Forward+, 1600×900; OBS was not running during these measurements). Regenerate with `python3 tools/make_world_report.py`.

## LIVE_OPTIMIZED — per location

| location | FPS | GPU ms | worst frame ms | primitives | draw calls | night FPS / GPU ms | cast FPS / worst ms | activity |
|---|---|---|---|---|---|---|---|---|
| ritual_sanctuary | 30.0 | 30.54 | 39.0 | 1793090 | 247 | 31.2 / 30.89 | 28.4 / 42.92 | ✓ study: Study the spellbook on the altar |
| mage_training_grounds | 30.1 | 20.41 | 37.31 | 1296160 | 139 | 31.2 / 19.84 |  /  | ✓ practice: Practice strikes at the standing sto |
| mentors_tower | 30.2 | 15.78 | 36.94 | 818673 | 150 | 31.3 / 15.31 |  /  | ✓ study: Read the mentor's notes on advanced cas |
| ancient_spell_library | 30.1 | 15.32 | 37.39 | 258403 | 67 | 31.3 / 19.14 |  /  | ✓ study: Study the Warding Glyph on the spell le |
| academy_courtyard | 30.0 | 18.02 | 38.26 | 426496 | 168 | 31.2 / 18.02 |  /  | ✓ read: Read the founder's plaque on the fountai |
| advanced_magic_arena | 30.0 | 17.73 | 36.92 | 446381 | 173 | 31.2 / 13.67 | 29.2 / 36.43 | ✓ practice: Run a casting drill in the arena |
| academy_gardens | 30.1 | 17.29 | 37.86 | 918097 | 128 | 31.3 / 16.48 |  /  | ✓ collect: Gather medicinal herbs in the gardens |
| great_library | 30.0 | 17.63 | 35.42 | 635242 | 81 | 31.2 / 17.51 |  /  | ✓ study: Read the rare grimoire on the central l |
| ancient_grove | 30.0 | 21.36 | 36.41 | 2178254 | 214 | 31.3 / 23.23 |  /  | ✓ meditate: Rest a hand on the eldest tree and l |
| forgotten_forest_shrine | 30.2 | 18.45 | 35.44 | 892532 | 137 | 31.3 / 17.68 |  /  | ✓ study: Read the runic glyphs on the shrine sto |
| luminous_river | 30.1 | 16.7 | 35.99 | 1686353 | 150 | 31.3 / 23.92 |  /  | ✓ collect: Fill a flask with luminous river wate |
| waterfall_crossing | 30.1 | 17.02 | 35.87 | 2041314 | 125 | 31.3 / 22.57 |  /  | ✓ meditate: Meditate on the bridge before the fa |
| village_square | 30.1 | 14.46 | 36.66 | 638912 | 351 | 31.3 / 19.19 | 29.1 / 37.01 | ✓ collect: Draw water from the well |
| lantern_market | 30.1 | 15.07 | 38.3 | 728030 | 247 | 31.3 / 16.95 |  /  | ✓ trade: Trade for dried herbs at the market |
| craft_workshop | 30.1 | 15.82 | 36.32 | 604268 | 385 | 31.3 / 16.74 |  /  | ✓ inspect: Inspect the craftsman's tools |
| village_observatory | 30.1 | 14.23 | 35.52 | 646320 | 142 | 31.2 / 15.31 |  /  | ✓ observe: Observe the sky through the brass tel |
| crystal_entrance | 30.2 | 17.77 | 39.09 | 1610723 | 225 | 31.3 / 20.89 |  /  | ✓ inspect: Examine the miners' crates at the cav |
| luminous_crystal_hall | 30.1 | 14.21 | 37.25 | 1145149 | 148 | 31.2 / 14.77 | 28.9 / 36.85 | ✓ collect: Chip a small shard from a crystal clu |
| underground_lake | 30.1 | 14.41 | 35.6 | 76466 | 60 | 31.3 / 10.99 | 29.5 / 37.72 | ✓ meditate: Meditate at the still lake's edge |
| ancient_vault | 30.0 | 14.07 | 35.33 | 54510 | 46 | 31.3 / 12.75 |  /  | ✓ study: Read the inscription carved beside the  |
| mountain_path | 30.0 | 14.8 | 35.87 | 814818 | 149 | 31.3 / 12.79 |  /  | ✓ offer: Add a stone to the trail cairn |
| cliff_overlook | 30.0 | 13.74 | 36.41 | 1013912 | 165 | 31.3 / 14.05 |  /  | ✓ observe: Take in the view over the sea of clou |
| celestial_observatory | 30.1 | 13.87 | 35.51 | 447906 | 67 | 31.2 / 13.78 |  /  | ✓ study: Align the armillary sphere to the stars |
| cloud_temple | 30.1 | 14.52 | 35.82 | 227100 | 123 | 31.3 / 12.72 | 29.6 / 35.53 | ✓ pray: Offer a quiet prayer in the Cloud Temple |

GPU ms across all visits: min 13.74, median 16.25, max 33.36. Locations under 30 FPS: none.

## LIVE_OPTIMIZED — streaming transitions

| # | from → to | total ms | preload wait ms | unload ms | build ms (frames) | worst step ms | nav bake ms | static MB | video MB | nodes | areas | nav regions | layout hash |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | (start) → sanctuary | 3304 | 0 | 0 | 1681 (12) | 394.32 | 160 | 226.9 | 734.6 | 577 | 1 | 1 |  |
| 1 | sanctuary → mentor_tower | 2226 | 0 | 59 | 723 (7) | 500.54 | 126 | 223.0 | 645.0 | 565 | 1 | 1 |  |
| 2 | mentor_tower → sanctuary | 3048 | 0 | 62 | 1483 (12) | 389.91 | 154 | 229.4 | 780.8 | 579 | 1 | 1 |  |
| 3 | sanctuary → arcane_library | 1947 | 0 | 62 | 434 (6) | 186.77 | 101 | 242.9 | 662.7 | 629 | 1 | 1 |  |
| 4 | arcane_library → sanctuary | 2906 | 0 | 61 | 1312 (10) | 394.87 | 178 | 250.2 | 822.7 | 579 | 1 | 1 |  |
| 5 | sanctuary → academy | 1779 | 0 | 63 | 266 (7) | 95.95 | 133 | 243.8 | 695.3 | 696 | 1 | 1 |  |
| 6 | academy → great_library | 1766 | 0 | 67 | 263 (6) | 123.76 | 99 | 227.5 | 653.8 | 500 | 1 | 1 |  |
| 7 | great_library → academy | 1866 | 0 | 60 | 278 (6) | 100.7 | 182 | 226.8 | 689.7 | 696 | 1 | 1 |  |
| 8 | academy → sanctuary | 3026 | 0 | 65 | 1406 (12) | 391.6 | 207 | 233.3 | 817.1 | 579 | 1 | 1 |  |
| 9 | sanctuary → ancient_grove | 2810 | 0 | 64 | 1261 (6) | 816.6 | 140 | 258.9 | 675.0 | 492 | 1 | 1 |  |
| 10 | ancient_grove → river_valley | 2519 | 0 | 65 | 1021 (8) | 556.64 | 123 | 270.5 | 721.4 | 475 | 1 | 1 |  |
| 11 | river_valley → village | 2440 | 0 | 66 | 937 (7) | 618.78 | 121 | 282.6 | 801.8 | 1676 | 1 | 1 |  |
| 12 | village → observatory_hill | 1678 | 0 | 64 | 172 (5) | 69.29 | 99 | 253.2 | 752.8 | 445 | 1 | 1 |  |
| 13 | observatory_hill → village | 2333 | 0 | 64 | 805 (7) | 574.72 | 154 | 259.4 | 753.6 | 1676 | 1 | 1 |  |
| 14 | village → crystal_caverns | 2496 | 0 | 57 | 962 (10) | 420.61 | 161 | 251.5 | 762.7 | 424 | 1 | 1 |  |
| 15 | crystal_caverns → deep_caverns | 1728 | 0 | 62 | 217 (6) | 76.34 | 101 | 249.5 | 733.9 | 225 | 1 | 1 |  |
| 16 | deep_caverns → crystal_caverns | 2342 | 0 | 61 | 841 (9) | 357.24 | 121 | 251.6 | 762.4 | 424 | 1 | 1 |  |
| 17 | crystal_caverns → village | 2344 | 0 | 65 | 810 (7) | 569.96 | 122 | 255.8 | 762.8 | 1676 | 1 | 1 |  |
| 18 | village → highland_path | 2860 | 0 | 68 | 1329 (6) | 1025.33 | 120 | 293.0 | 781.2 | 278 | 1 | 1 |  |
| 19 | highland_path → celestial_summit | 1955 | 0 | 68 | 448 (6) | 264.59 | 93 | 272.9 | 810.6 | 306 | 1 | 1 |  |
| 20 | celestial_summit → highland_path | 2741 | 0 | 63 | 1214 (6) | 878.78 | 122 | 273.1 | 810.8 | 278 | 1 | 1 |  |
| 21 | highland_path → village | 2362 | 0 | 63 | 837 (7) | 571.93 | 144 | 278.9 | 811.5 | 1676 | 1 | 1 |  |
| 22 | village → river_valley | 2488 | 0 | 59 | 992 (7) | 539.27 | 87 | 247.6 | 767.6 | 475 | 1 | 1 |  |
| 23 | river_valley → ancient_grove | 2953 | 0 | 63 | 1359 (7) | 820.38 | 211 | 274.8 | 836.5 | 492 | 1 | 1 |  |
| 24 | ancient_grove → sanctuary | 2934 | 0 | 64 | 1372 (12) | 386.86 | 147 | 269.6 | 916.2 | 579 | 1 | 1 |  |
| 25 | sanctuary → arcane_library | 1951 | 0 | 54 | 440 (5) | 199.03 | 134 | 258.6 | 793.2 | 629 | 1 | 1 |  |
| 26 | arcane_library → sanctuary | 2994 | 0 | 57 | 1400 (11) | 389.14 | 179 | 265.8 | 950.0 | 579 | 1 | 1 |  |
| 27 | sanctuary → arcane_library | 1912 | 0 | 61 | 404 (5) | 164.23 | 100 | 258.7 | 790.0 | 629 | 1 | 1 |  |
| 28 | arcane_library → sanctuary | 2973 | 0 | 62 | 1411 (10) | 387.81 | 148 | 265.9 | 950.0 | 579 | 1 | 1 |  |

Transition total: median 2401.0 ms, max 3048 ms. Instantiated areas after every transition: [1]; navigation regions: [1].

### Memory over repeated visits (Sanctuary rows)

| visit | static MB | texture MB | video MB | nodes |
|---|---|---|---|---|
| 1 | 227.9 | 527.5 | 772.0 | 579 |
| 2 | 256.2 | 616.2 | 936.0 | 579 |
| 3 | 265.8 | 623.1 | 950.0 | 579 |
| 4 | 265.9 | 623.1 | 950.0 | 579 |

## CINEMATIC — per location

| location | FPS | GPU ms | worst frame ms | primitives | draw calls | night FPS / GPU ms | cast FPS / worst ms | activity |
|---|---|---|---|---|---|---|---|---|
| ritual_sanctuary | 15.4 | 64.87 | 72.11 | 2483554 | 248 | 15.4 / 66.8 | 13.0 / 121.71 | ✓ study: Study the spellbook on the altar |
| mage_training_grounds | 18.8 | 52.95 | 60.52 | 2157455 | 148 | 19.2 / 53.2 |  /  | ✓ practice: Practice strikes at the standing sto |
| mentors_tower | 25.2 | 39.45 | 46.44 | 1319311 | 156 | 27.8 / 36.37 |  /  | ✓ study: Read the mentor's notes on advanced cas |
| ancient_spell_library | 28.9 | 34.33 | 40.7 | 294771 | 66 | 28.5 / 35.39 |  /  | ✓ study: Study the Warding Glyph on the spell le |
| academy_courtyard | 29.2 | 33.88 | 37.46 | 507443 | 148 | 28.0 / 35.89 |  /  | ✓ read: Read the founder's plaque on the fountai |
| advanced_magic_arena | 26.5 | 37.34 | 43.25 | 510016 | 173 | 31.2 / 32.2 | 23.5 / 55.41 | ✓ practice: Run a casting drill in the arena |
| academy_gardens | 24.4 | 40.69 | 45.62 | 1493993 | 122 | 25.3 / 40.01 |  /  | ✓ collect: Gather medicinal herbs in the gardens |
| great_library | 27.0 | 36.78 | 41.0 | 658662 | 82 | 27.9 / 36.15 |  /  | ✓ study: Read the rare grimoire on the central l |
| ancient_grove | 20.0 | 49.62 | 55.35 | 2646944 | 194 | 20.8 / 48.82 |  /  | ✓ meditate: Rest a hand on the eldest tree and l |
| forgotten_forest_shrine | 24.3 | 40.96 | 46.2 | 1255987 | 113 | 24.1 / 42.11 |  /  | ✓ study: Read the runic glyphs on the shrine sto |
| luminous_river | 24.5 | 40.5 | 44.75 | 2201045 | 145 | 19.9 / 51.06 |  /  | ✓ collect: Fill a flask with luminous river wate |
| waterfall_crossing | 25.1 | 39.6 | 47.0 | 2025197 | 99 | 21.2 / 47.76 |  /  | ✓ meditate: Meditate on the bridge before the fa |
| village_square | 25.5 | 39.05 | 45.48 | 1021092 | 489 | 27.5 / 36.65 | 22.5 / 53.12 | ✓ collect: Draw water from the well |
| lantern_market | 26.9 | 36.8 | 41.46 | 1015180 | 248 | 25.6 / 39.51 |  /  | ✓ trade: Trade for dried herbs at the market |
| craft_workshop | 26.2 | 37.87 | 45.48 | 836697 | 389 | 24.8 / 40.83 |  /  | ✓ inspect: Inspect the craftsman's tools |
| village_observatory | 25.0 | 39.73 | 45.77 | 1116398 | 150 | 23.5 / 43.22 |  /  | ✓ observe: Observe the sky through the brass tel |
| crystal_entrance | 26.4 | 37.56 | 42.14 | 1637755 | 206 | 25.9 / 39.01 |  /  | ✓ inspect: Examine the miners' crates at the cav |
| luminous_crystal_hall | 30.3 | 32.73 | 37.93 | 174588 | 96 | 36.1 / 27.7 | 21.9 / 67.55 | ✓ collect: Chip a small shard from a crystal clu |
| underground_lake | 38.9 | 25.39 | 29.04 | 96462 | 51 | 43.1 / 23.11 | 32.8 / 35.52 | ✓ meditate: Meditate at the still lake's edge |
| ancient_vault | 38.9 | 25.4 | 33.08 | 72220 | 38 | 43.3 / 22.95 |  /  | ✓ study: Read the inscription carved beside the  |
| mountain_path | 28.8 | 34.44 | 39.97 | 1493090 | 125 | 31.6 / 31.79 |  /  | ✓ offer: Add a stone to the trail cairn |
| cliff_overlook | 27.9 | 35.43 | 48.98 | 1626842 | 130 | 34.6 / 28.83 |  /  | ✓ observe: Take in the view over the sea of clou |
| celestial_observatory | 31.7 | 31.19 | 46.25 | 554646 | 82 | 36.2 / 27.55 |  /  | ✓ study: Align the armillary sphere to the stars |
| cloud_temple | 27.7 | 35.79 | 40.24 | 551126 | 130 | 31.3 / 31.79 | 24.1 / 63.75 | ✓ pray: Offer a quiet prayer in the Cloud Temple |

GPU ms across all visits: min 25.39, median 37.45, max 64.87. Locations under 30 FPS: ['academy_courtyard', 'academy_gardens', 'advanced_magic_arena', 'ancient_grove', 'ancient_spell_library', 'cliff_overlook', 'cloud_temple', 'craft_workshop', 'crystal_entrance', 'forgotten_forest_shrine', 'great_library', 'lantern_market', 'luminous_river', 'mage_training_grounds', 'mentors_tower', 'mountain_path', 'ritual_sanctuary', 'village_observatory', 'village_square', 'waterfall_crossing'].

## CINEMATIC — streaming transitions

| # | from → to | total ms | preload wait ms | unload ms | build ms (frames) | worst step ms | nav bake ms | static MB | video MB | nodes | areas | nav regions | layout hash |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | (start) → sanctuary | 7251 | 0 | 0 | 2373 (12) | 387.02 | 291 | 245.8 | 863.3 | 657 | 1 | 1 | e59079ab9613 |
| 1 | sanctuary → mentor_tower | 2656 | 0 | 40 | 1156 (7) | 513.16 | 148 | 238.5 | 821.1 | 565 | 1 | 1 | 99ebfb88662b |
| 2 | mentor_tower → sanctuary | 3553 | 0 | 43 | 2007 (11) | 392.62 | 202 | 297.9 | 957.8 | 659 | 1 | 1 | e59079ab9613 |
| 3 | sanctuary → arcane_library | 2206 | 0 | 66 | 694 (6) | 255.03 | 83 | 306.3 | 839.1 | 629 | 1 | 1 | eb7e8f7d6177 |
| 4 | arcane_library → sanctuary | 3703 | 0 | 39 | 2129 (11) | 387.17 | 232 | 318.7 | 999.7 | 659 | 1 | 1 | e59079ab9613 |
| 5 | sanctuary → academy | 2221 | 0 | 60 | 699 (6) | 223.32 | 137 | 308.8 | 871.4 | 696 | 1 | 1 | 81446b7b198e |
| 6 | academy → great_library | 1972 | 0 | 38 | 500 (6) | 149.42 | 108 | 290.6 | 830.6 | 500 | 1 | 1 | b04aeba8da57 |
| 7 | great_library → academy | 2225 | 0 | 33 | 682 (6) | 214.15 | 149 | 291.1 | 865.8 | 696 | 1 | 1 | 81446b7b198e |
| 8 | academy → sanctuary | 3588 | 0 | 44 | 1960 (11) | 398.69 | 237 | 301.1 | 994.1 | 659 | 1 | 1 | e59079ab9613 |
| 9 | sanctuary → ancient_grove | 3212 | 0 | 38 | 1640 (6) | 835.52 | 235 | 322.9 | 860.4 | 528 | 1 | 1 | 796b1a98c599 |
| 10 | ancient_grove → river_valley | 3598 | 0 | 49 | 1667 (9) | 564.49 | 173 | 334.0 | 882.8 | 475 | 1 | 1 | d892ba1a552a |
| 11 | river_valley → village | 4151 | 0 | 48 | 2641 (8) | 692.13 | 130 | 344.8 | 939.1 | 1676 | 1 | 1 | ca2593db5450 |
| 12 | village → observatory_hill | 1806 | 0 | 35 | 358 (4) | 173.56 | 103 | 313.0 | 890.1 | 445 | 1 | 1 | 61ffb02b6a02 |
| 13 | observatory_hill → village | 2854 | 0 | 39 | 1272 (8) | 571.32 | 201 | 321.2 | 890.9 | 1676 | 1 | 1 | ca2593db5450 |
| 14 | village → crystal_caverns | 2729 | 0 | 41 | 1218 (9) | 370.94 | 181 | 311.9 | 900.0 | 416 | 1 | 1 | fab42043ab83 |
| 15 | crystal_caverns → deep_caverns | 2062 | 0 | 33 | 573 (8) | 167.86 | 108 | 309.9 | 868.0 | 225 | 1 | 1 | 285b40f7f195 |
| 16 | deep_caverns → crystal_caverns | 2700 | 0 | 34 | 1131 (9) | 358.35 | 156 | 312.0 | 896.5 | 416 | 1 | 1 | fab42043ab83 |
| 17 | crystal_caverns → village | 2769 | 0 | 36 | 1225 (8) | 565.26 | 189 | 317.2 | 896.8 | 1676 | 1 | 1 | ca2593db5450 |
| 18 | village → highland_path | 3101 | 0 | 37 | 1589 (6) | 1014.83 | 208 | 352.4 | 915.3 | 278 | 1 | 1 | 2a61d33055dc |
| 19 | highland_path → celestial_summit | 2298 | 0 | 35 | 834 (6) | 271.43 | 109 | 334.6 | 948.0 | 306 | 1 | 1 | 4d6ca8096490 |

Transition total: median 2729 ms, max 4151 ms. Instantiated areas after every transition: [1]; navigation regions: [1].

## Autonomous traversal (tools/mock_brain.py over the bridge, headless)

Journeys succeeded: 23/23; locations visited: 24/24; activities succeeded: 23; casts: 5 (all finished: False); elapsed 713.8 s.

Honesty checks (scenic / unfinished landmarks must not be travelable):

* `dragon_peaks` (scenic): reachable flag = False, travel_to → unknown location 'dragon_peaks'
* `sky_spire` (scenic): reachable flag = False, travel_to → unknown location 'sky_spire'
* `sunken_citadel` (unfinished): reachable flag = False, travel_to → unknown location 'sunken_citadel'
* `sunken_citadel (by id)` (): reachable flag = —, travel_to → unknown location 'sunken_citadel'

Final world state: skills {'arcane_orb': 2.32}, inventory {'crystal_shard': 0, 'herbs': 2, 'luminous_water': 1, 'well_water': 1}, 17 knowledge entries.

