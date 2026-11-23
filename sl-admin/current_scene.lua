-- current_scene.lua: SotaLoreAdmin.CurrentScene, which scene the player is in, written to
-- Lua/sotalore-current-scene.json each time it changes.
--
-- Not for upload: the companion app (sotalore/companion) reads it to file screenshots and spoken notes under the
-- scene they were taken in. A plugin can't take a screenshot or see one being taken, so the companion matches a
-- screenshot's time to the scene entered just before it; that is why the file says when the scene was entered.
--
-- Why it watches every frame instead of using ShroudOnSceneLoaded: a scene change reloads every add-on. The plugin
-- starts again during the loading screen, while there is no scene, and the ShroudOnSceneLoaded for that load never
-- reaches it (seen in game, 2026-11-23, #2). So each frame it asks whether a scene is loaded and which one, and
-- writes the file when that differs from what it last wrote. The scene appearing while the plugin watches is the
-- moment it was entered.
--
-- Used by: main.lua (ShroudOnStart, ShroudOnUpdate, ShroudOnSceneUnloaded, ShroudOnLogOut).

local util = SotaLoreAdmin.util
local jstr, jnum = util.jstr, util.jnum

local M = {}
SotaLoreAdmin.CurrentScene = M

local written = nil   -- rawName .. "|" .. character of the scene last written, nil before the first write

-- The time now in whole seconds since 1970 UTC. (The game's os.time() has a fraction, 1795468515.36479.)
local function now()
    return math.floor(os.time())
end

-- A text, or null when it is missing or empty (the game returns "" for "none").
local function jtext(s)
    if type(s) ~= "string" or s == "" then return "null" end
    return jstr(s)
end

-- A time (whole seconds since 1970, UTC) as ISO 8601 UTC text: "2026-11-23T20:15:03Z".
local function isoUtc(t)
    return os.date("!%Y-%m-%dT%H:%M:%SZ", t)
end

-- The scene the player is in, or nil on the login screen and while a scene loads.
local function loadedScene()
    local scene = ShroudGetSceneInfo()
    if not scene or not scene.loaded or scene.rawName == nil or scene.rawName == "" then return nil end
    return scene
end

-- What the file written before says, when it names a scene the player was in: its rawName, character and
-- enteredAt, or nothing.
local function previous()
    local body = util.readFile(SotaLoreAdmin.files.currentScene)
    if not body or not body:find('"state":"inScene"', 1, true) then return nil end
    return body:match('"rawName":"([^"]*)"'), body:match('"character":"([^"]*)"'),
        tonumber(body:match('"enteredAt":(%d+)'))
end

local function write(body)
    local path, err = util.writeFile(SotaLoreAdmin.files.currentScene, body)
    if not path then ShroudConsoleLog("Could not write the current scene file: " .. tostring(err)) end
    return path ~= nil
end

-- Writes `scene` (from ShroudGetSceneInfo) as the scene the player is in. `exact` is false when the plugin didn't
-- see the scene appear (it started in it), so `enteredAt` is the time it started instead.
local function writeScene(scene, character, enteredAt, exact)
    local dungeonName = ShroudGetCurrentDungeonName and ShroudGetCurrentDungeonName() or ""
    local dungeonOwner = ShroudGetCurrentDungeonOwner and ShroudGetCurrentDungeonOwner() or ""
    return write(util.header("currentScene")
        .. ',"state":"inScene"'
        .. ',"name":' .. jtext(scene.name)
        .. ',"rawName":' .. jtext(scene.rawName)
        .. ',"dungeonName":' .. jtext(dungeonName)
        .. ',"dungeonOwner":' .. jtext(dungeonOwner)
        .. ',"character":' .. jtext(character)
        .. ',"enteredAt":' .. jnum(enteredAt)
        .. ',"enteredAtUtc":' .. jstr(isoUtc(enteredAt))
        .. ',"enteredAtExact":' .. tostring(exact)
        .. ',"writtenAt":' .. jnum(now())
        .. '}\n')
end

-- The plugin started: at game start, after /lua reload, and after every scene change. Already in a scene (a /lua
-- reload), write it now, keeping the last file's entry time when it was the same scene and character, since that
-- time is the real one. Otherwise (the loading screen, the login screen) M.tick writes it when the scene appears.
function M.start()
    written = nil
    local scene = loadedScene()
    if not scene then return end
    local character = ShroudGetPlayerName()
    local prevRaw, prevCharacter, prevEntered = previous()
    local ok
    if prevRaw == scene.rawName and prevCharacter == character and prevEntered then
        ok = writeScene(scene, character, prevEntered, true)
    else
        ok = writeScene(scene, character, now(), false)
    end
    if ok then written = scene.rawName .. "|" .. tostring(character) end
end

-- Every frame: when a scene is loaded and it isn't the one last written (or another character is in it), the
-- player has just entered it.
function M.tick()
    local scene = loadedScene()
    if not scene then return end
    local character = ShroudGetPlayerName()
    local key = scene.rawName .. "|" .. tostring(character)
    if key == written then return end
    written = key   -- set even when the write fails, so a failing write is tried once, not every frame
    writeScene(scene, character, now(), true)
end

-- No scene: "loading" (left a scene, the next one isn't loaded yet) or "loggedOut" (back at the login screen).
local function writeNoScene(state)
    written = nil
    local t = now()
    write(util.header("currentScene")
        .. ',"state":' .. jstr(state)
        .. ',"name":null,"rawName":null,"dungeonName":null,"dungeonOwner":null,"character":null'
        .. ',"enteredAt":' .. jnum(t)
        .. ',"enteredAtUtc":' .. jstr(isoUtc(t))
        .. ',"enteredAtExact":true'
        .. ',"writtenAt":' .. jnum(t)
        .. '}\n')
end

-- The scene is unloading (a zone line, a recall, a logout). Written so the companion knows the scene has ended,
-- and so that M.start, after the reload that follows, doesn't take the next scene for the one in the file even
-- when it is the same scene entered again.
function M.sceneUnloaded()
    writeNoScene("loading")
end

-- Back at the login screen.
function M.loggedOut()
    writeNoScene("loggedOut")
end
