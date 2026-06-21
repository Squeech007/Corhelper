--[[
CorHelper

Scoped-down roll-maintenance addon, modeled after the "renew my buffs, nothing
fancier" pattern used by Puphelper for PUP maneuvers.

Deliberately excluded vs AshitaRoller: gamble mode, automated Snake Eye /
Random Deal / Fold selection, party chat alerts, quick mode. Double-Up never
gambles on an overshoot, since its add is a fresh 1-11 roll and an overshoot
can never be guaranteed bust-proof.

Attribution:
  Roll lucky/unlucky data and the packet-parsing approach are referenced
  from AshitaRoller by Selindrile (Ashita port by towbes/matix, v0.3 by
  Lumlum, v0.4 interface-16 rework by Palmer). Command system, keyword
  aliases, settings handling, and double-up logic are independently written.

Commands (both /corhelper and /ch work):
  /ch on | off                 - toggle the helper loop
  /ch status                   - show current settings
  /ch roll1 <id|name>          - set roll 1 by ability id or keyword (e.g. cor, hunter)
  /ch roll2 <id|name>          - set roll 2 by ability id or keyword
  /ch set1 <name> set2 <name>  - set both rolls in one line, e.g. /ch set1 cor set2 hunter
  /ch double on | off          - toggle auto double-up
  /ch engaged on | off         - only fire while engaged
  /ch debug on | off           - verbose diagnostic output
  /ch list                     - print roll ability ids
]]

addon = addon or {}
addon.name    = 'CorHelper'
addon.version = '0.1.6'
addon.author  = 'Spok'
addon.desc    = 'Minimal roll-maintenance helper. Roll data and packet-parsing approach referenced from AshitaRoller by Selindrile (Ashita port by towbes/matix, v0.3 by Lumlum, v0.4 interface-16 rework by Palmer); decision logic and feature set independently written and intentionally scoped down.'

require('common')

----------------------------------------------------------------------------
-- Static data
----------------------------------------------------------------------------

-- ability id -> { name, buffid, lucky, unlucky }
local rollInfo = {
    [105] = {name="Chaos Roll",       buffid=317, lucky=4,  unlucky=8},
    [98]  = {name="Fighter's Roll",   buffid=310, lucky=5,  unlucky=9},
    [101] = {name="Wizard's Roll",    buffid=313, lucky=5,  unlucky=9},
    [112] = {name="Evoker's Roll",    buffid=324, lucky=5,  unlucky=9},
    [103] = {name="Rogue's Roll",     buffid=315, lucky=5,  unlucky=9},
    [114] = {name="Corsair's Roll",   buffid=326, lucky=5,  unlucky=9},
    [108] = {name="Hunter's Roll",    buffid=320, lucky=4,  unlucky=8},
    [113] = {name="Magus's Roll",     buffid=325, lucky=2,  unlucky=6},
    [100] = {name="Healer's Roll",    buffid=312, lucky=3,  unlucky=7},
    [111] = {name="Drachen Roll",     buffid=323, lucky=4,  unlucky=8},
    [107] = {name="Choral Roll",      buffid=319, lucky=2,  unlucky=6},
    [99]  = {name="Monk's Roll",      buffid=311, lucky=3,  unlucky=7},
    [106] = {name="Beast Roll",       buffid=318, lucky=4,  unlucky=8},
    [109] = {name="Samurai Roll",     buffid=321, lucky=2,  unlucky=6},
    [102] = {name="Warlock's Roll",   buffid=314, lucky=4,  unlucky=8},
    [115] = {name="Puppet Roll",      buffid=327, lucky=3,  unlucky=7},
    [104] = {name="Gallant's Roll",   buffid=316, lucky=3,  unlucky=7},
    [116] = {name="Dancer's Roll",    buffid=328, lucky=3,  unlucky=7},
    [118] = {name="Bolter's Roll",    buffid=330, lucky=3,  unlucky=9},
    [119] = {name="Caster's Roll",    buffid=331, lucky=2,  unlucky=7},
    [122] = {name="Tactician's Roll", buffid=334, lucky=5,  unlucky=8},
    [303] = {name="Miser's Roll",     buffid=336, lucky=5,  unlucky=7},
    [110] = {name="Ninja Roll",       buffid=322, lucky=4,  unlucky=8},
    [302] = {name="Allies' Roll",     buffid=335, lucky=3,  unlucky=10},
    [305] = {name="Avenger's Roll",   buffid=338, lucky=4,  unlucky=8},
    [121] = {name="Blitzer's Roll",   buffid=333, lucky=4,  unlucky=9},
    [120] = {name="Courser's Roll",   buffid=332, lucky=3,  unlucky=9},
    [391] = {name="Runeist's Roll",   buffid=600, lucky=4,  unlucky=8},
    [390] = {name="Naturalist's Roll",buffid=339, lucky=3,  unlucky=7},
}

-- shorthand keyword -> ability id, e.g. /ch roll1 cor or /ch set1 hunter
local rollKeywords = {
    chaos    = 105,
    chr      = 105,
    drk      = 105,

    fighter  = 98,
    fighters = 98,
    ftr      = 98,

    wizard   = 101,
    wizards  = 101,
    wiz      = 101,

    evoker   = 112,
    evokers  = 112,
    evo      = 112,

    rogue    = 103,
    rogues   = 103,
    rog      = 103,

    cor      = 114,
    corsair  = 114,
    corsairs = 114,

    hunter   = 108,
    hunters  = 108,
    hun      = 108,

    magus    = 113,
    mag      = 113,

    healer   = 100,
    healers  = 100,
    heal     = 100,

    drachen  = 111,
    drg      = 111,

    choral   = 107,
    brd      = 107,

    monk     = 99,
    monks    = 99,
    mnk      = 99,

    beast    = 106,
    bst      = 106,

    samurai  = 109,
    sam      = 109,

    warlock  = 102,
    warlocks = 102,
    wlk      = 102,

    puppet   = 115,
    pup      = 115,

    gallant  = 104,
    gallants = 104,
    pld      = 104,

    dancer   = 116,
    dancers  = 116,
    dnc      = 116,

    bolter   = 118,
    bolters  = 118,
    bolt     = 118,
    thf      = 118,

    caster   = 119,
    casters  = 119,
    cast     = 119,

    tactician = 122,
    tact      = 122,

    miser    = 303,
    mis      = 303,

    ninja    = 110,
    nin      = 110,

    allies   = 302,
    ally     = 302,

    avenger  = 305,
    avengers = 305,
    avg      = 305,

    blitzer  = 121,
    blitzers = 121,
    blz      = 121,

    courser  = 120,
    coursers = 120,
    crs      = 120,

    runeist  = 391,
    run      = 391,

    naturalist = 390,
    nat        = 390,
}

local function resolveRollArg(arg)
    if not arg then return nil end
    local id = tonumber(arg)
    if id and rollInfo[id] then return id end
    local keyword = arg:lower()
    local kwId = rollKeywords[keyword]
    if kwId and rollInfo[kwId] then return kwId end
    return nil
end

----------------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------------

local defaults = {
    enabled    = false,
    roll1      = 114, -- Corsair's Roll
    roll2      = 109, -- Samurai Roll
    autodouble = true,
    engaged    = false,
    debug      = false,
}

local settings = {}
for k, v in pairs(defaults) do settings[k] = v end

-- no ashita.settings module on interface-16; config is a Lua table literal
-- in config\addons\CorHelper\<playername>.lua
local function configPath(playername)
    return string.format('%sconfig\\addons\\%s\\%s.lua', AshitaCore:GetInstallPath(), addon.name, playername)
end

local function serialize_table(tbl)
    local result = "{\n"
    for k, v in pairs(tbl) do
        local keyStr = type(k) == 'string' and string.format('["%s"]', k) or string.format('[%s]', tostring(k))
        if type(v) == 'string' then
            result = result .. '  ' .. keyStr .. ' = "' .. v .. '",\n'
        else
            result = result .. '  ' .. keyStr .. ' = ' .. tostring(v) .. ',\n'
        end
    end
    return result .. '}'
end

local function load_config()
    local p = GetPlayerEntity()
    if not p or not p.Name then return nil end
    local path = configPath(p.Name)
    if not ashita.fs.exists(path) then return nil end

    local ok, loaded = pcall(function() return loadfile(path)() end)
    if not ok or not loaded then return nil end

    -- merge over defaults so an old/partial save file doesn't leave new
    -- fields nil after an addon update
    local cfg = {}
    for k, v in pairs(defaults) do cfg[k] = v end
    for k, v in pairs(loaded) do cfg[k] = v end
    return cfg
end

local function save_config()
    local p = GetPlayerEntity()
    if not p or not p.Name then return end

    local dir = string.format('%sconfig\\addons\\%s\\', AshitaCore:GetInstallPath(), addon.name)
    ashita.fs.create_dir(dir)

    local file = io.open(configPath(p.Name), 'w')
    if file then
        file:write('return ' .. serialize_table(settings))
        file:close()
    end
end

local function msg(text)
    print('\31\200[\31\05CorHelper\31\200]\31\207 ' .. text)
end

local COLOR_ON    = '\31\030' -- green
local COLOR_OFF   = '\31\167' -- red/grey
local COLOR_VALUE = '\31\005' -- yellow/highlight
local COLOR_RESET = '\31\207'

local function colorBool(b, onText, offText)
    if b then
        return COLOR_ON .. (onText or 'ON') .. COLOR_RESET
    else
        return COLOR_OFF .. (offText or 'OFF') .. COLOR_RESET
    end
end

local function colorValue(text)
    return COLOR_VALUE .. tostring(text) .. COLOR_RESET
end

local function printStatus()
    msg('Status:')
    msg('  Running: ' .. colorBool(settings.enabled))
    msg('  Roll 1: ' .. colorValue(rollInfo[settings.roll1] and rollInfo[settings.roll1].name or 'unset'))
    msg('  Roll 2: ' .. colorValue(rollInfo[settings.roll2] and rollInfo[settings.roll2].name or 'unset'))
    msg('  Auto Double-Up: ' .. colorBool(settings.autodouble))
    msg('  Engaged Only: ' .. colorBool(settings.engaged))
    msg('  Debug: ' .. colorBool(settings.debug))
end

----------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------

local FIRE_DELAY = 3          -- seconds between fired actions, to avoid spam

-- separate timers for two different concerns: tick() fires roll1/roll2 on its
-- own slow poll, while the double-up reaction needs to fire promptly right
-- after a roll-result packet lands. Sharing one timer meant a fresh roll
-- resetting the clock would then block the double-up check that follows
-- a split-second later, since not enough time had passed yet.
local lastRollFireTime = 0
local lastDoubleUpFireTime = 0

-- Double-Up can't be queued the instant a roll lands — the roll's own cast
-- animation is still locking the client out of another /ja. Instead of
-- firing immediately, we mark a target time and let the regular render-tick
-- poll (which already runs every TICK_INTERVAL) fire it once that's passed.
local DOUBLEUP_ANI_DELAY = 2 -- seconds to wait out the prior roll's ani lock
local pendingDoubleUpAt = nil

-- set when a packet tells us we should double up but Double-Up's own
-- recast hadn't cleared yet; tick() retries until it does
local doubleUpWanted = false
local doubleUpWantedRoll = nil -- which rollInfo entry triggered it, for redundant checks

local haveRoll1, haveRoll2, haveBust = false, false, false

local player, playerid = nil, nil

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------

local function haveBuffId(buffid)
    local pdata = AshitaCore:GetMemoryManager():GetPlayer()
    if not pdata then return false end
    local buffs = pdata:GetBuffs()
    if not buffs then return false end
    for _, v in pairs(buffs) do
        if v == buffid then return true end
    end
    return false
end

local function updateBuffState()
    local r1 = rollInfo[settings.roll1]
    local r2 = rollInfo[settings.roll2]
    haveRoll1 = r1 and haveBuffId(r1.buffid) or false
    haveRoll2 = r2 and haveBuffId(r2.buffid) or false
    haveBust  = haveBuffId(309)
end

-- interface-16 has no ffxi.recast module; recast timers are read directly
-- off the memory manager's recast timer slots instead
local function getAbilityRecast(abilityId)
    local mmRecast = AshitaCore:GetMemoryManager():GetRecast()
    if not mmRecast then return 0 end
    for x = 0, 31 do
        local id = mmRecast:GetAbilityTimerId(x)
        local timer = mmRecast:GetAbilityTimer(x)
        if id == abilityId and timer > 0 then
            return math.floor(timer / 60)
        end
    end
    return 0
end

local function updateRecast()
    player    = GetPlayerEntity()
    playerid  = AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0)
end

-- Auto Double-Up behavior:
--   - Stop on lucky.
--   - Double-Up when below lucky.
--   - Stop when above lucky (no bust gamble; Double-Up's add is 1-11, so an
--     overshoot can never be guaranteed bust-proof).
local function shouldDoubleUp(rollNum, info)
    return rollNum < info.lucky
end

----------------------------------------------------------------------------
-- Action queue (single delayed fire per tick, like a manual macro would be)
----------------------------------------------------------------------------

local function queueAbility(name)
    AshitaCore:GetChatManager():QueueCommand(1, '/ja "' .. name .. '" <me>')
end

local function tick()
    if not settings.enabled then return end
    if player == nil then return end

    -- fire a scheduled double-up once its ani-lock wait has elapsed
    if pendingDoubleUpAt and os.time() >= pendingDoubleUpAt then
        msg('Doubling up...')
        queueAbility('Double-Up')
        lastDoubleUpFireTime = os.time()
        pendingDoubleUpAt = nil
    end

    -- retry a double-up that was wanted but blocked by Double-Up's own
    -- recast at the time; once that recast clears, schedule it now
    if doubleUpWanted and not pendingDoubleUpAt then
        if haveBust or not doubleUpWantedRoll or not haveBuffId(doubleUpWantedRoll.buffid) then
            -- the roll buff that triggered this is gone (busted, expired,
            -- or replaced) — drop the stale retry instead of blocking forever
            doubleUpWanted = false
            doubleUpWantedRoll = nil
        else
            local recast = getAbilityRecast(194) -- JAid 123, RecastId 194
            if recast == 0 then
                local now = os.time()
                if now - lastDoubleUpFireTime >= FIRE_DELAY then
                    pendingDoubleUpAt = now + DOUBLEUP_ANI_DELAY
                    doubleUpWanted = false
                    doubleUpWantedRoll = nil
                    if settings.debug then
                        msg('DEBUG retried Double-Up recast cleared, scheduling for +' .. DOUBLEUP_ANI_DELAY .. 's')
                    end
                end
            end
        end
    end

    local now = os.time()
    if pendingDoubleUpAt or doubleUpWanted then return end
    if now - lastRollFireTime < FIRE_DELAY then return end

    if settings.engaged and player.Status ~= 1 then return end
    if haveBuffId(16) or haveBuffId(261) then return end -- amnesia/impairment
    if haveBust then return end -- no auto-fold by design; wait it out or handle manually

    -- Phantom Roll has a shared recast across both roll slots; firing roll2
    -- right after roll1 gets rejected by the server until this clears
    local phantomRecast = getAbilityRecast(193) -- JAid 97, RecastId 193
    if phantomRecast > 0 then return end

    if not haveRoll1 then
        local info = rollInfo[settings.roll1]
        if info then
            msg('Rolling ' .. info.name .. '...')
            queueAbility(info.name)
            lastRollFireTime = now
        end
        return
    end

    if not haveRoll2 then
        local info = rollInfo[settings.roll2]
        if info then
            msg('Rolling ' .. info.name .. '...')
            queueAbility(info.name)
            lastRollFireTime = now
        end
        return
    end
end

----------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------

local settingsLoaded = false

ashita.events.register('load', 'corhelper_load_cb', function()
    -- player entity may not exist yet here; actual load happens on first render
end)

ashita.events.register('unload', 'corhelper_unload_cb', function()
    save_config()
end)

local lastTickTime = 0
local TICK_INTERVAL = 0.5 -- seconds; render fires 30-60x/sec, no need to poll that often

ashita.events.register('d3d_present', 'corhelper_present_cb', function()
    if not settingsLoaded then
        local p = GetPlayerEntity()
        if p then
            local loaded = load_config()
            if loaded then settings = loaded end -- else: keep the defaults already in `settings`
            settingsLoaded = true
            msg('Loaded.')
            printStatus()
        else
            return -- wait for player entity before doing anything else
        end
    end

    local now = os.clock()
    if now - lastTickTime < TICK_INTERVAL then return end
    lastTickTime = now

    updateRecast()
    if player == nil then return end
    updateBuffState()
    tick()
end)

-- Read the roll result off the action packet purely to decide on a single
-- double-up — no branching between abilities, no gamble logic, no reading
-- past what's needed for the lucky/unlucky comparison described above.
ashita.events.register('packet_in', 'corhelper_packet_in_cb', function(e)
    local id = e.id
    local packet = e.data_raw
    if id ~= 0x028 then return end
    if not playerid or playerid == 0 then return end

    local actorId = ashita.bits.unpack_be(packet, 40, 32)
    local category = ashita.bits.unpack_be(packet, 82, 4)
    local param = ashita.bits.unpack_be(packet, 86, 10)

    if category ~= 6 then return end
    if not rollInfo[param] then return end
    if actorId ~= playerid then return end

    -- only the first target's first action param (the roll number) matters here
    local bit = 150
    local targetId = ashita.bits.unpack_be(packet, bit, 32)
    local rollNum = ashita.bits.unpack_be(packet, bit + 36 + 27, 17)

    if targetId ~= playerid then return end

    local info = rollInfo[param]
    if not info then return end

    msg(info.name .. ' result: ' .. rollNum .. ' (lucky: ' .. info.lucky .. ')')

    if settings.debug then msg('DEBUG packet reached, autodouble=' .. tostring(settings.autodouble)) end

    if settings.autodouble then
        -- read recast live here rather than trusting the throttled render-cycle
        -- value, since this packet can arrive between render ticks
        local liveDoubleUpRecast = getAbilityRecast(194) -- JAid 123, RecastId 194
        local wantsDouble = shouldDoubleUp(rollNum, info)

        if settings.debug then
            msg('DEBUG recast=' .. tostring(liveDoubleUpRecast) .. ' shouldDouble=' .. tostring(wantsDouble))
        end

        if wantsDouble and liveDoubleUpRecast > 0 then
            doubleUpWanted = true
            doubleUpWantedRoll = info
            if settings.debug then
                msg('DEBUG Double-Up still on its own recast (' .. liveDoubleUpRecast .. 's), will retry')
            end
        end

        if liveDoubleUpRecast == 0 and wantsDouble then
            local now = os.time()
            if now - lastDoubleUpFireTime >= FIRE_DELAY then
                pendingDoubleUpAt = now + DOUBLEUP_ANI_DELAY
                doubleUpWanted = false
                doubleUpWantedRoll = nil
                if settings.debug then
                    msg('DEBUG scheduling Double-Up for +' .. DOUBLEUP_ANI_DELAY .. 's (ani-lock wait)')
                end
            elseif settings.debug then
                msg('DEBUG double-up throttled, ' .. (now - lastDoubleUpFireTime) .. 's since last')
            end
        end
    end
end)

----------------------------------------------------------------------------
-- Commands
----------------------------------------------------------------------------

ashita.events.register('command', 'corhelper_command_cb', function(e)
    local args = e.command:args()
    if #args == 0 then return false end
    local cmdName = args[1]:lower()
    if cmdName ~= '/corhelper' and cmdName ~= '/ch' then return false end

    local sub = args[2]

    -- /ch set1 cor set2 hunter -- sets both rolls in one line
    if sub == 'set1' or sub == 'set2' then
        local argCount = #args
        local i = 2
        while i <= argCount do
            if args[i] == 'set1' and args[i + 1] then
                local id = resolveRollArg(args[i + 1])
                if id then
                    settings.roll1 = id
                    msg('Roll 1 set to ' .. rollInfo[id].name)
                else
                    msg('Unknown roll: ' .. tostring(args[i + 1]))
                end
                i = i + 2
            elseif args[i] == 'set2' and args[i + 1] then
                local id = resolveRollArg(args[i + 1])
                if id then
                    settings.roll2 = id
                    msg('Roll 2 set to ' .. rollInfo[id].name)
                else
                    msg('Unknown roll: ' .. tostring(args[i + 1]))
                end
                i = i + 2
            else
                i = i + 1
            end
        end
        save_config()
        return true
    end

    if sub == 'on' then
        settings.enabled = true
        msg('Enabled.')
    elseif sub == 'off' then
        settings.enabled = false
        msg('Disabled.')
    elseif sub == 'roll1' and args[3] then
        local id = resolveRollArg(args[3])
        if id then
            settings.roll1 = id
            msg('Roll 1 set to ' .. rollInfo[id].name)
        else
            msg('Unknown roll: ' .. tostring(args[3]) .. '. Use /ch list.')
        end
    elseif sub == 'roll2' and args[3] then
        local id = resolveRollArg(args[3])
        if id then
            settings.roll2 = id
            msg('Roll 2 set to ' .. rollInfo[id].name)
        else
            msg('Unknown roll: ' .. tostring(args[3]) .. '. Use /ch list.')
        end
    elseif sub == 'double' then
        if args[3] == 'on' then
            settings.autodouble = true
            msg('Auto double-up enabled.')
        elseif args[3] == 'off' then
            settings.autodouble = false
            msg('Auto double-up disabled.')
        end
    elseif sub == 'engaged' then
        if args[3] == 'on' then
            settings.engaged = true
            msg('Will only fire while engaged.')
        elseif args[3] == 'off' then
            settings.engaged = false
            msg('Will fire regardless of engaged status.')
        end
    elseif sub == 'debug' then
        if args[3] == 'on' then
            settings.debug = true
            msg('Debug output enabled.')
        elseif args[3] == 'off' then
            settings.debug = false
            msg('Debug output disabled.')
        end
    elseif sub == 'status' then
        printStatus()
    elseif sub == 'list' then
        for id, info in pairs(rollInfo) do
            msg(id .. ': ' .. info.name .. ' (lucky ' .. info.lucky .. ', unlucky ' .. info.unlucky .. ')')
        end
    else
        if sub then
            msg('Unknown command: ' .. colorValue(sub))
        end
        msg('Commands: on | off | status | roll1 <id|name> | roll2 <id|name> | set1 <name> set2 <name> | double on/off | engaged on/off | debug on/off | list')
        printStatus()
    end

    save_config()
    return true
end)
