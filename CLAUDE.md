# CLAUDE.md (sladmin)

@../hq/AGENTS.md
@../hq/LUA-PLUGINS.md

Notes for the `sladmin` agent, working on `sl-admin` (SotaLore Admin), the in-game Lua add-on for site admins:
recipe, item, per-scene find and game-skill exports, as files for the site. The rules every SotA Lore plugin follows
(naming, how the game runs a package, saved data, testing) are in `LUA-PLUGINS.md` above; this file is what's
particular to `sl-admin`.

## What this is

- The package is the `sl-admin/` folder (flat, its name is the slug); everything at the top of the repo is outside
  the package, so the store never sees it. Its global table is `SotaLoreAdmin`, its command `/sladmin`.
- `sl-admin` has a twin helper set in `sotalore/slskills` (`sl-skills/core.lua`: `jstr`, `jnum`, `header`,
  `writeFile`). A fix to one of those here is checked there, and the other way round.
- `EXPORT-FORMAT.md`: **the contract with the app (and later the companion), and yours to keep accurate.**
  Change it in the same PR as any export change, flag breaking changes in it, and add a line to its changelog.
  The app reads exactly what it describes.
- `FROM-THE-APP.md` lives in the app repo, at `docs/FROM-THE-APP.md` of `sotalore/sotalore`: written by the
  app-side agent (how the site uses exports, the site's data model, and the requests R1 to R6 from before issues).
  Read it from the side-by-side checkout (`../sotalore/docs/FROM-THE-APP.md`, after a pull) or with
  `gh api repos/sotalore/sotalore/contents/docs/FROM-THE-APP.md -H 'Accept: application/vnd.github.raw'`.
  **Read it, never edit it**; the `FROM-THE-APP.md` here is only a pointer to it.
- **Requests from the app are issues in this repo** (`gh issue list -R sotalore/sladmin`). Answer in the issue.
  When the answer changes an export, change the plugin and `EXPORT-FORMAT.md` in the same PR, with
  "Closes #N"; when nothing changes, a comment is the whole answer. Tell the reader agents about a merged format
  change (see "Messages" in `AGENTS.md`).
- Real example outputs live in the app, in `spec/fixtures/plugin-examples/` of `sotalore/sotalore`. When a format
  changes, open an issue there to refresh them. `.gitignore` ignores `sotalore-*.json` so game output is never
  committed here by accident.

## Code organisation

Darren is new to Lua, so the layout is meant to be easy to read: each file does one job and starts with a
comment saying what it is for. This is the pattern the game's own multi-file example addon uses.

`sl-admin/`:

| File | Job |
|------|-----|
| `core.lua` | creates the one global table `SotaLoreAdmin`; shared helpers in `SotaLoreAdmin.util` (JSON writing, text clipping, file writing, `perItem`) and file names in `SotaLoreAdmin.files` |
| `recipes_export.lua` | `SotaLoreAdmin.RecipeExport`: known recipes to JSON files, the "already exported" list |
| `gear_samples.lua` | `SotaLoreAdmin.GearSamples`: what expanded gear tooltips say a piece is made of (components, exceptional, enchantments, masterworks, failures, sockets), kept as distinct samples for the items file's `craftedSamples`; captured from gear anywhere while capture is on |
| `item_details.lua` | `SotaLoreAdmin.ItemDetails`: captures what item tooltips say (quest item, tool, no trade, salvage lists) by hovering, `/sladmin capture` |
| `items.lua` | `SotaLoreAdmin.Items`: the items file for the bags; exports only new or changed items (`new`), everything (`all`) or marks them exported (`baseline`), in time slices |
| `finds_data.lua` | `SotaLoreAdmin.Finds`: the per-scene find list (items, creatures, nodes), saving it, writing the finds file |
| `finds_ui.lua` | `SotaLoreAdmin.FindsUI`: the small finds window |
| `items_ui.lua` | `SotaLoreAdmin.ItemsUI`: the small items window (counts, the Capture switch, the item export buttons) |
| `recipes_ui.lua` | `SotaLoreAdmin.RecipesUI`: the recipe list and recipe windows, with the recipe export buttons |
| `toolbar_ui.lua` | `SotaLoreAdmin.ToolbarUI`: the toolbar `/sladmin` opens, with a button for each of the three windows above |
| `hoverlog.lua` | `SotaLoreAdmin.HoverLog`: a diagnostic (`/sladmin hoverlog`) that writes the tooltip text of items under the mouse to chat (shortened) and in full to `sotalore-hoverlog.txt` |
| `targetlog.lua` | `SotaLoreAdmin.TargetLog`: a diagnostic (`/sladmin targetlog`) that writes each new target to chat (name, id, dead, health, focus, the stats Animal Lore shows, pet or party member), to learn whether targeting can add creatures to the finds that are never fought |
| `game_skills.lua` | `SotaLoreAdmin.GameSkills`: every skill in the game (`ShroudGetAllSkills`) to `sotalore-game-skills.json`, `/sladmin gameskills`; not uploaded, copied into the repo for the app's code |
| `current_scene.lua` | `SotaLoreAdmin.CurrentScene`: the scene the player is in and when it was entered, to `sotalore-current-scene.json` when it changes (checked every frame, since a scene change reloads the plugin); not uploaded, the companion reads it to file screenshots by scene |
| `main.lua` | the only file with `ShroudOn...` callbacks, the `/sladmin` command and the key binding; read it first |

Data modules (`recipes_export`, `finds_data`) know nothing about windows. They tell a window about
changes through a hook (`Finds.onChange`, `RecipeExport.onProgress`) that the UI file sets.

## What the finds window is for

Darren walks a scene with the finds window up, then saves the list for upload. The goal is to keep the
site's data about each scene current:

1. **Scene information**: the scene's kind flags, player cap and level/skill caps (`info`).
2. **Creatures** that can be met in the scene (the ones fought, and since sl-admin 0.11.0 the ones only targeted, under `seen`, for the site to review) and **what they can drop**.
3. **Gathering nodes** available in the scene and **what each yields**.

A creature's drops are only attributed when its corpse is field dressed (the node is the creature's name).
Corpse loot taken another way has no source, so some drops are unattributed.

### The gathering activities

Five kinds, which the data does not label (a node name that is also in `creatures` is a creature):

- **Mining** (a "Copper Vein"), **forestry** (a Pine or Maple tree), **foraging** (a garlic or cotton plant):
  a node in the world that is harvested. `ShroudOnGatherResults` gives its name and loot.
- **Field dressing**: not a world node. The creature is killed first (or its corpse is found), then the
  corpse is "skinned". `ShroudOnGatherResults` gives the creature's name as the node.
- **Fishing**: an activity of its own, very different from the others. **Not handled yet**; Darren will
  cover it later. Do not assume it fits the node model.

### Interrupted harvests (open problem)

The first four activities can be interrupted. Finished: `ShroudOnGatherResults` fires. Interrupted: it
does **not** fire, and the node (or corpse) simply becomes a lootable thing holding the items earned so far.
Those items arrive through `ShroudOnItemsGained` with no source, so they are counted under `items` but
never under `nodes`. Darren wants to find a better way to track these; it may not be possible.

**Ruled out: the mouse.** Tracking what the player points at (`ShroudGet*UnderMouse`) will not work: the game
can loot any corpse near where the player stands without clicking it, and a corpse that needs skinning is
skinned automatically. The player often never points at the thing.

Untested ideas:

- At the moment of a gain, read the current target (the target log, `/sladmin targetlog`, showed it switches between nearby combatants several times a second, so this is a weak signal) (`ShroudHasTarget`, `ShroudGetTargetName`,
  `ShroudIsTargetDead`); a corpse being looted or skinned may still be the target. Test with a debug log
  before building on it.
- Use the combat lines: a `death` line with a time and creature key, then loot arriving soon after, suggests
  that corpse. Nearby auto-loot can take several corpses at once, so this is a guess to label as one.
- Map an item name to the node(s) that gave it in completed harvests in the same scene, and attribute
  an unattributed gain only when that mapping is unique (Iron Ore comes from "Iron Vein" and nothing else).
  Label such guesses in the file; never mix them into the confirmed `nodes`.
- If either of the first two ideas works, it might also attribute plain corpse loot (not just interrupted
  skinning) to the creature it came from.

## Environment

- Both game clients' `Lua\sl-admin` folders are **Windows junctions** to this repo's package folder,
  `C:\dev\sotalore\sladmin\sl-admin`, so both clients run the plugin as it is here. Edit here, never through the
  game's path (that once failed with odd "file already exists" errors). Remove a junction with `cmd /c rmdir
  <path>`, which removes only the link; a recursive delete can go through it into the repo.
- Output files (`sotalore-recipes-new.json`, `-recipes-all.json`, `-recipes-one.json`, `-item-catalog.json`,
  `-scene-finds.json`, `-game-skills.json`, and `-current-scene.json` for the companion; named after the site's
  navigation since 0.11.0) land in the client's
  `Lua/` folder.
- `sl-recipes.account.json` was this plugin's saved data before the rename to `sl-admin`.
- **The 256 KB saved-data limit has bitten twice.** On 2026-10-24 `sl-admin.account.json` reached 256,011 bytes
  (210 KB of it item details) and a day of captures was lost at a reload. Since 0.12.0 the item details are stored
  small, gear samples live in the character scope, and saving calls `util.flush()`, which writes at once and warns
  in chat when the game refuses. On 2026-10-30 the account file reached 260 KB (620 items) and the game refused it
  again, so since 0.14.0 the details are in a data file. Saved files start with a UTF-8 byte-order mark.
- **Data files:** saves are spaced 11 seconds apart, and a forced save refused as `tooOften` (at unload) goes to a
  second file, which is read first and removed by the next write of the main file. Whether a write works during
  unload is untested.
- Edit tool calls in parallel on one file can collide; make edits to one file one at a time.

## Slash commands, windows, saved data

- `sl-admin`: `/sladmin` (until 2026-10-18 `/slore`) on its own, and the key binding, open the toolbar (since 0.13.0;
  before, the recipe list). Subcommands: `recipes` (toggle the recipe list), `export`,
  `exportall`, `baseline`, `new` (open the list showing only recipes "Export new" would export), `items` (new or
  changed items), `itemsall`, `baselineitems`, `finds` (toggle the finds window), `savefinds`, `clearfinds`,
  `gatherlog`, `checkrecipes`, `capture`, `hoverlog`, `targetlog`, `gameskills`; other text searches the recipe list. The command's help
  text must be at most 120 characters.
- An add-on may own at most **8 windows**. `sl-admin` (since 0.13.0): the toolbar, the finds, items and recipe list
  windows (4), and up to 4 recipe windows (before: the list, the finds window and up to 6 recipe windows).
- `sl-admin`'s windows (0.13.0): the toolbar "SotaLore Admin" has three buttons, Finds, Items and Recipes, each
  opening or closing one window. "SotaLore Finds" tracks a scene; "SotaLore Items" (built like it) shows the bag,
  capture and gear sample counts, with the Capture switch and the New items / All items buttons; "SotaLore Recipes"
  is the searchable recipe list with the recipe export buttons. Each window's position and size are saved by the game
  per window id, so the old ids (`recipelist`, `sotalorefinds`) were kept.
- `sl-admin` account-scope saved variables: `exported` (recipe ids already exported; "Export new" = not in it),
  `itemSigs` (a fingerprint per item for what was last exported; no catalog of items is kept), `finds`
  (the per-scene list), `track` (tracking toggle). Character scope: `gearSamples` (gear breakdowns, a list, each with
  its tooltip text, key and an exported flag).
- `sl-admin` data file (since 0.14.0, in `Lua/AddonData/sl-admin/`): `item_details.json`, `{ items = ... }`, the captured
  tooltips (stored small: name, text, a short fingerprint `fp` and `rev`, everything else worked out from the text). Until
  then it was the saved variable `itemDetails`, which the first save moves over and removes.

## API facts learned in play (docs are at https://catnipgames.net/lua/reference.html)

- Read the docs by downloading the page, stripping the HTML to text and searching it; a summarising
  fetch loses detail. The docs and the live API can differ and the API version moves (it was 40).
- **Bag item `weight` and `value`: one item's figures from API 41, the whole stack's before.** Up to API 40
  they were stack totals although documented as "one item", so the plugin divided by `quantity` (`perItem`). The
  game fixed that in API 41 (and added `totalWeight`/`totalValue` for the stack), but the plugin kept dividing,
  which made every weight and value of sl-admin 0.11.0 and earlier on API 41+ far too small and different for each
  stack size (Darren noticed Animal Hide changing on every "New items" export, 2026-10-21). Since 0.11.1
  `util.perItem` divides only when `ShroudLuaApiVersion` < 41. Lesson: when the plugin works around an API bug,
  gate the workaround on the API version, and re-read the docs when the API version moves. Before API 41, some
  stacks report no `quantity` (missing or 0; three potions, found by the site agent): the number can't be made
  per-item, so `util.perItem` returns nil (null in the file) and `ItemDetails.perItem` then tries the captured tooltip, which
  shows "Quantity: 638 | Stack Weight: 191.4 | Stack Value: 6,380" for a stack (so that potion is 0.3 and 10 gold).
  Before 0.8.1 it passed the raw stack total through. The tooltip's "Merchant pays" for a stack is also a whole-stack
  price (divided by the quantity), and tooltip numbers use thousands commas ("6,380").
- **Gear tooltips, expanded with Ctrl, say where each effect comes from** (seen 2026-10-24 with the hover log): sections
  separated by blank lines, one per component (a name such as "Bronze Weapon Blade" or "Bronze Sheet (2)", then its
  effect lines), "Exceptional (+1)", "Enchantment(s):" and "Masterwork(s):" (each line ending "(-20 Maximum
  Durability)", failures as "(3) Enchantment Failure (-75 Max Durability)"), "Socket: Blades (2)", "On Hit (10%): ...",
  and "Durability: 48/49 (Max 165-135+30)" (base, lost, gained). Not expanded ("Hold control to expand"), all effects are
  added up in one list. The component names on gear are role names, not always the item's ("Bronze Weapon Blade" for
  Bronze Longsword Blade). A component item's own tooltip lists what it adds under "Material Crafting Bonus". Blank
  lines matter here, but `item_details.lua` stores tooltip text without them.
- **A bracket at the end of a name can be part of it.** "Focus Battery Necklace, Common (L)" and "... Common" are two
  items with different keys (so are "Bolt of Cotton Cloth" and "... (Vintage)"), but a crafted item's tooltip title also
  ends in brackets its name lacks ("Boots +15 (Leather Boots +15)", "ZRandom (Small Leather Bag)" for a renamed bag). So
  `util.itemsNamed` tries the whole name first, and capture only drops the bracket for a crafted tooltip (0.13.1, #274).
- **A crafted item's salvage list is its own** (it depends on the materials), not the kind's, although it shares
  the base item's `key`. The tooltip title of crafted gear ends with the base item's name in brackets; the plugin
  exports the title (`details.title`) so the site can use it.
- **`ShroudGetRecipe(id)` can return nil for a recipe `ShroudGetKnownRecipes` lists** (first seen with newly
  learned recipes: the detail window said "You no longer know this recipe" and exports silently dropped
  them). `util.getRecipe(id, categoryKey)` falls back to `ShroudGetRecipeBook(categoryKey)`; exports now warn in
  chat about recipes they could not read, and `/sladmin checkrecipes` lists the unreadable ones. On Darren's
  character 103 of 1,234 known recipes failed (Alchemy gem fragment and fracture recipes, Tanning fishing-trophy
  recipes); the recipe book had them. Before 0.5.2 they were silently left out of every export. Cause unknown.
- **The game stops a callback that runs longer than 1 second (5 seconds while the plugin starts).** The guide says
  to spread work across frames or use `ShroudRegisterPeriodic`. Long jobs here (the recipe export, `/sladmin
  checkrecipes`) work in slices of `util.sliceLimit` seconds per frame, cut by time as well as count because
  recipes with many group slots are far slower to read than simple ones. `util.slow(what, since)` writes a
  "SotaLore slow: ..." line to chat when a step takes over 0.3 s, to find the one that is too slow. A single
  call that is itself slow (`ShroudGetRecipeBook` for a whole craft skill, saving a big saved variable) cannot
  be sliced. On 2026-10-18 the slow-step messages showed `ShroudGetRecipeBook("Crafting_Alchemy")` taking
  1.8 s (Tanning 0.3 s; the day before it had been fast enough), so the game stopped it, and the old code read the
  book again every frame (it marked a book as read only after the call returned, and bag changes emptied the
  cache). Since sl-admin 0.10.1: a book is marked as tried before the call and read at most once per export, in
  a frame of its own; recipes got from a book are kept (saved variables `bookRecipes`, and `needBook` for which
  recipes need one) and later exports use those copies; and `ShroudOnStart`, which gets 5 s, reads the books
  those recipes need (`util.readNeededBooks`), so `/lua reload` refreshes the copies. **A call that can take over
  a second belongs in `ShroudOnStart` or not at all**; never retry a call the game may have stopped (a burst of
  errors makes the game switch the plugin off).
- **A stopped callback must leave the job's state consistent.** The 0.7.1 export once wrote 10 recipes twice: the game
  stopped a callback (the watchdog) after a batch of recipes had been stored but before the position was
  advanced, so the next frame read the same batch again. `ShroudGetKnownRecipes` itself lists every id once (checked:
  1,234 entries, 1,234 different recipes). Since 0.7.2 the export stores each recipe under its id and advances
  one recipe at a time, so reading a recipe again changes nothing. Keep any multi-frame job idempotent like that.
- A bag item's `key` (`item:` + 32 hex) is the same key recipes use for ingredients and results; this is the
  only game item id there is. Recipe `id` is a signed 32-bit integer and can be negative, and it names one version of a recipe: when the game
  changes a recipe (three Shrines had one ingredient replaced, seen 2026-10-20) it gets a new id and the old one is gone.
- `ShroudOnItemsGained` ("Recently Looted") excludes items already owned, moves, equipping, login and
  scene changes, but includes bank/chest/vendor/crafting-station takes. The API has no locked flag.
- There is no call that lists a scene's creatures. Two ways to see them: combat lines (`ShroudOnCombatEvents`,
  only fights involving the player, party or pet) and the **target** (`ShroudOnTargetChanged`, since sl-admin
  0.11.0 the finds' `seen` list). A creature's level shows only when it is the target and Animal Lore allows it.
- **The target** (tested 2026-10-20 with `/sladmin targetlog`): it follows the target frame, the locked target or
  else the closest combatant, so creatures walking past or fighting each other become the target; with several
  near it switches between them a few times a second. `ShroudGetTargetId` is stable per individual (and can be
  negative; only -1 means none). The level shows at once or never. Every creature has focus. **Nothing tells a
  creature from an NPC ("Fighter", "Practice Dummy") or a player**: all show health and focus only when Animal
  Lore can't read them. Clues that do exist: another player's pet or companion has a second line with its owner
  ("You can call me Ned\n<Nedley Mandingo>"), an away player has "[AFK]" after the name. A decoration pet
  ("Mylo") read like a level 3 creature with every stat. Not every nearby player becomes the target.
- `ShroudOnGatherResults` node is the resource name for mining and harvesting, and **the creature's name
  for field dressing**. Its `items` include "N Producer Experience" entries that are not items (filtered).
  An interrupted harvest sends nothing (see "Interrupted harvests" above). Corpse and chest loot has no
  source.
- Group slots in recipes list at most 30 choices; the larger "any item of this kind" groups are truncated
  (`complete: false` in `groups`). Names repeat, so groups are identified by `groupKey`.
- **Screenshots: nothing in the API** (checked at API 58, #2). No call takes a screenshot, hides or shows the HUD,
  presses keys or runs game commands, and no callback says a screenshot was taken. `ShroudIsUIActive()` only reads
  whether the HUD is shown (no callback; check it each frame). The game's keys: `TakeScreenshot` F11,
  `ScreenshotMode` (hides the interface) F10. The QA client saves to `%USERPROFILE%\Pictures\SotA\DEV\` as
  `SotA_MM-DD-YY_HH-MM_N.png`; the regular client to `Pictures\SotA\` (confirmed).
- **A scene change reloads every add-on** (the docs say so in passing: "/lua reload, or a scene change"). The new
  instance starts during the loading screen, with no scene loaded, and **it evidently never gets
  `ShroudOnSceneLoaded` for that load** (inferred: the first 0.16.0 scene file, written from that callback and from
  `ShroudOnStart`, never changed on a zone line, 2026-11-23, #2). To act on entering a scene,
  check `ShroudGetSceneInfo().loaded` and the scene's name each frame. `ShroudOnSceneUnloaded` reaches the old
  instance (untested). Module state lasts only one scene visit.
- **The game's `os.time()` returns a fraction** (`1795468515.36479`). Use `math.floor(os.time())` for whole seconds.
- The game has a hotkey that switches tooltips off. While they are off the `...UnderMouse` calls see nothing,
  so `/sladmin capture` and `/sladmin hoverlog` capture nothing, and the plugin can't tell that from "not pointing at
  an item". Nothing to do about it for now; the capture-on message in chat reminds the player.

## Working style

- Keep `main.lua` in the plain style it has: local helpers, comments for the non-obvious "why".
- One topic per commit. Do not commit or push unless Darren asks; when he does, push straight to `main` (no
  branches or PRs). Say in the commit message what is verified in game and what is not.
- Before starting work, find or open its issue in this repo (`bug` or `enhancement`), and put "Closes #N" in the commit message.
