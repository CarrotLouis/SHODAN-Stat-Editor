-- SHODAN Stat Editor Offline: Stat Editor's own panel (stat_editor.lua, the in-game mod) in a desktop window,
-- editing the game's data files instead of the running game. The files are decrypted into memory as the game
-- holds them, the panel finds and edits them there, and Install writes the changed ones into the game folder.
-- host.lua [stat_editor.lua]
local here = (debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './')
package.path = here .. '?.lua;' .. package.path

local ffi = require('ffi')
local shim = require('engine_shim')
local G = require('gamedata')
local D = require('hostdata')
local I = require('install')
local U = require('update')
local AR = require('armory')
local ARM = require('armor_ui')
local EARLY=require('zh_ui').early
local eui=rawget(_G,'SHODAN_EUI')
if eui then
    -- Data-only host: never creates a GDI window or handles desktop input.
    shim.open=function() shim.w,shim.h=1400,1080 end
    shim.pump=function() return true end
    shim.set_title=function() end
    shim.message_box=function(text) log_eui_warning=text;return 1 end
    shim.transition=function() end
end
-- An opt-in render check for the packaged application; never writes game files.
local qa_output = os.getenv('SHODAN_QA_OUTPUT')
if qa_output then U.available = false end
local V = require('vehicles')

pcall(ffi.cdef, 'uint64_t GetTickCount64(void);')
local function clock() return tonumber(ffi.C.GetTickCount64()) / 1000 end
local log_file = nil
local function log(text)
    if not log_file then
        I.mkdirs(I.logs)
        log_file = io.open(I.logs .. '/SHODANStatEditorHost.log', 'w')
        if not log_file then log_file = false end
    end
    if log_file then log_file:write(os.date('%H:%M:%S '), text, '\n'); log_file:flush() end
end

local BACK = { 255, 12, 15, 19 }
local RED = { 255, 255, 72, 60 }   -- the Enemy Editor's (editor.lua's red)
local GOLD, WHITE, MUTED, WARN, GOOD = { 255, 255, 213, 0 }, { 255, 238, 242, 246 }, { 255, 153, 171, 184 },
                                        { 255, 255, 150, 60 }, { 255, 120, 220, 140 }

local function centred(text, y, size, c)
    shim.text(text, (shim.w - shim.text_width(text, size)) / 2, y, size, c)
end

-- a screen with a few lines of text (loading, problems)
local function screen(lines)
    if eui then return end
    shim.fill(0, 0, shim.w, shim.h, BACK)
    local s = shim.h / 1080
    local y = shim.h * 0.42
    for k, line in ipairs(lines) do
        line=EARLY(line)
        local size = (k == 1 and 34 or 20) * s
        centred(line, y, size, k == 1 and GOLD or MUTED)
        y = y + size * 1.8
    end
    shim.present()
end

local function fatal(text)
    text=EARLY(text)
    if eui then error(text) end
    log('stopped: ' .. text)
    if qa_output then local f=io.open(qa_output..'/failure.txt','wb');if f then f:write(text);f:close() end
    else shim.message_box(text, 0x10) end
    os.exit(1)
end

-- ---------------------------------------------------------------- start
-- where the window was when it last closed: its top left, and its height once the user resized it (window.txt: x y [h])
local PLACE = I.home .. '/window.txt'
local function saved_place()
    local f = io.open(PLACE, 'r')
    local text = f and f:read('*a') or ''
    if f then f:close() end
    local x, y, h = text:match('^(%-?%d+) (%-?%d+) ?(%d*)')
    return x and { tonumber(x), tonumber(y), tonumber(h) } or nil
end

local THEME=I.home..'/theme.txt'
local function main()
    local theme_file=io.open(THEME,'rb')
    local selected_theme=theme_file and theme_file:read('*a') or 'light'
    if theme_file then theme_file:close() end
    shim.set_theme(selected_theme:match('dark') and 'dark' or 'light')
    shim.open('SHODAN 数值编辑器 4.5.1-r2', saved_place())
    shim.pump()
    local migrated = I.migrate()
    if migrated then log('copied ' .. migrated .. ' files from the CowboyBingus folder') end
    screen({ 'SHODAN Stat Editor Offline', 'Looking for Helldivers 2...' })
    local exe_dir = here:gsub('[/\\]app[/\\]$', ''):gsub('[/\\]$', '')
    local game = I.find_game(exe_dir)
    if not game then
        fatal('Helldivers 2 was not found.\n\nWrite the path of its folder (the one holding "data") into\n'
              .. I.home:gsub('/', '\\') .. '\\game folder.txt\nand start again.')
    end
    local backup_count,backup_error=I.migrate_compat_backups(game)
    if backup_count==nil then fatal(backup_error) end
    if backup_count>0 then log('migrated to official backups: '..backup_count) end
    log('game: ' .. game)
    AR.log = log
    log('hash search: ' .. (G.native and 'native, every core' or 'Lua (shodan_hash.dll not found)'))
    screen({ 'SHODAN Stat Editor Offline', 'Reading the game\'s data files...' })
    shim.pump()
    local shipped=I.shipped_originals(exe_dir,game)
    local shipped_count=0;for _ in pairs(shipped or {}) do shipped_count=shipped_count+1 end
    log('verified shipped originals: '..shipped_count)
    local originals, ours, problems, count, observed = I.originals(game,shipped)
    -- Validated legacy originals remain usable if copying into originals is denied.
    -- The official writer still requires a successful disk backup before game writes.
    for name,data in pairs(I.compat_originals or {}) do
        if not (shipped and shipped[name]) then originals[name]=data end
        ours[name]=true
    end
    for i=#problems,1,-1 do
        local name=problems[i]:match('^(generated_[%w_]+%.dl_bin):')
        if name and I.compat_originals[name] then table.remove(problems,i) end
    end
    for _,warning in ipairs(I.compat_warnings or {}) do log(warning) end

    if count == 0 then fatal('No game data files in ' .. game) end
    local armor_file='generated_customization_passive_bonuses.dl_bin'
    local canonical,repaired,verified=require('armor_baseline').original(originals[armor_file],I.read(game..'/game.dll'))
    if canonical then originals[armor_file]=canonical end
    D.armor_defaults_verified=verified
    if repaired then log('armor baseline: replaced modified backup in memory with verified vanilla table; legacy backup retained') end
    local managed_path=I.home..'/managed-files.txt'
    local managed={}
    for name in (I.read(managed_path) or ''):gmatch('[^\r\n]+') do managed[name]=true end
    local managed_inputs={}
    local mod_management_enabled=false
    local working={};for name,data in pairs(originals) do working[name]=data end
    -- The installed values stay visible; the immutable references supply defaults.
    -- Armor stacking keeps its separately verified baseline.
    if not qa_output or os.getenv('SHODAN_QA_INSTALLED')=='1' then
        for name in pairs(shipped or {}) do
            local current=I.read(game..'/'..name)
            if current and not managed[name] then working[name]=current end
        end
    end
    for _, p in ipairs(D.load(game, working, originals)) do problems[#problems + 1] = p end
    AR.refresh(D.passives())
    AR.import_values = D.import_forge_values
    AR.init(game, I.home .. '/armory.ini')
    for _, p in ipairs(problems) do log('problem: ' .. p) end
    local loaded = 0
    for _ in pairs(D.files) do loaded = loaded + 1 end
    log(string.format('%d of %d files loaded, %d installed by an earlier install', loaded, count,
        (function() local n = 0; for _ in pairs(ours) do n = n + 1 end return n end)()))
    if loaded == 0 then
        fatal('None of the game\'s data files could be read:\n\n' .. table.concat(problems, '\n', 1, math.min(#problems, 8))
              .. '\n\nVerify the game files in Steam and start again.')
    end
    if #problems > 0 then
        shim.message_box(EARLY('Some of the game\'s data files are not as this editor expects; their stats cannot be edited:\n\n'
                         .. table.concat(problems, '\n', 1, math.min(#problems, 10))
                         .. '\n\nIf another tool changed them, verify the game files in Steam.'), 0x30)
    end

    -- the vehicles' handling (their physics, out of the game's archives): the panel offers it when this works
    local physics_ok, physics_why = pcall(V.load, (game:gsub('[/\\]game$', '')), log)
    if physics_ok and physics_why > 0 then rawset(_G, 'SHODAN_PHYSICS', V.shared)
    elseif not physics_ok then log('vehicle physics: not offered: ' .. tostring(physics_why)) end
    local patch = I.patch_installed(game)   -- this editor's patch archive in the game (its name), or nil

    -- ------------------------------------------------------------ the editor
    screen({ 'SHODAN Stat Editor Offline', 'Finding the stats...' })
    rawset(_G, 'SHODAN_OFFLINE', true)
    rawset(_G, 'SHODAN_OFFLINE_LAYOUT', require('layout'))
    rawset(_G, 'SHODAN_OFFLINE_DEFAULT_READ', function(address,size) return D.original_bytes(address,size) or (V.original_bytes and V.original_bytes(address,size)) end)
    rawset(_G, 'SHODAN_OFFLINE_LOADED_READ', function(address,size) return D.original_bytes(address,size,true) end)
    rawset(_G, 'SHODAN_OFFLINE_GAME', game)
    rawset(_G, 'SHODAN_OFFLINE_REGISTER_LAYOUT', D.register_original_layout)
    rawset(_G,'SHODAN_OFFLINE_TEXT',shim.take_text)
    rawset(_G,'SHODAN_OFFLINE_WHEEL',function() local value=shim.wheel or 0;shim.wheel=0;return value end)
    rawset(_G,'SHODAN_OFFLINE_ZH',require('zh_extra'))
    local reviewed_game=require('zh_game')
    rawset(_G,'SHODAN_OFFLINE_ZH_GAME',{translate=function(text) return reviewed_game.translate(text) or V.translate(text) end})
    rawset(_G,'SHODAN_OFFLINE_ZH_PARAMS',require('zh_params'))
    rawset(_G,'SHODAN_OFFLINE_ZH_REFERENCE',require('zh_reference'))
    rawset(_G,'SHODAN_OFFLINE_ZH_UI',require('zh_ui'))
    rawset(_G,'SHODAN_OFFLINE_TRANSITION',shim.transition)
    rawset(_G, 'SHODAN_OFFLINE_TABLES', function()
        local blocks = {}
        for name, file in pairs(D.files) do
            for _, header in ipairs(G.headers(file.p, file.n)) do
                blocks[#blocks+1] = { address = tonumber(ffi.cast('uintptr_t', file.p + header.at)),
                                     type = header.type, size = header.size, file = name }
            end
        end
        table.sort(blocks, function(a,b) return a.address < b.address end)
        return blocks
    end)
    if rawget(_G, 'SHODAN_OFFLINE_LANG') == nil then rawset(_G, 'SHODAN_OFFLINE_LANG', 'zh-Hans') end
    -- the panel's first language (until one is chosen in Settings): Windows' display language, if translated
    pcall(ffi.cdef, 'uint16_t GetUserDefaultUILanguage(void);')
    local id = ffi.C.GetUserDefaultUILanguage()
    local primary, sub = id % 1024, math.floor(id / 1024)
    if rawget(_G, 'SHODAN_OFFLINE_LANG') == nil then rawset(_G, 'SHODAN_OFFLINE_LANG', primary == 0x04 and ((sub == 2 or sub == 4) and 'zh-Hans' or 'zh-Hant')
                                      or primary == 0x19 and 'ru' or primary == 0x0A and 'es-419' or primary == 0x16 and 'pt-BR' or nil) end
    stingray = shim.engine()
    function update(dt) end
    local editor = arg and arg[1] or here .. 'stat_editor.lua'
    local chunk, why = loadfile(editor)
    if not chunk then fatal('Could not load ' .. editor .. ':\n' .. tostring(why)) end
    local ok, err = pcall(chunk)
    if not ok then fatal('Stat Editor did not start:\n' .. tostring(err)) end
    local state = rawget(_G, 'ShodanStatEditor')
    if type(state) ~= 'table' then fatal('Stat Editor did not start (no state).') end
    if state.phase == 'gave_up' then fatal('数据读取失败：' .. tostring(state.status)) end
    ARM.init(AR, D, I.home)
    ARM.on_change = function() state.writes = (state.writes or 0) + 1 end
    AR.frame = ARM.frame
    local corpses -- Initialized with the desktop API after queued values are loaded.
    ARM.tabs=state.desktop_tabs;ARM.navigate=state.desktop_navigate
    ARM.tr=state.tr;ARM.transition=shim.transition
    state.open_armor = AR.show
    local build = U.build(here)   -- app/build.txt: version, commit, channel
    shim.set_title('SHODAN 数值编辑器 4.5.1-r2')
    -- the host's own text in the panel's language, drawn with its font
    local function tr(text)
        if type(state.tr)~='function' then return text end
        -- The armor summary is appended after the install sentence. Translate
        -- the sentence on its own so the upstream end-anchored rule still matches.
        local result,suffix
        if type(text)=='string' then result,suffix=text:match('^(Installed %b().-values%.)(.*)$') end
        if result then return state.tr(result)..suffix end
        return state.tr(text)
    end
    if type(state.lang) == 'function' then shim.lang = state.lang end

    -- ------------------------------------------------------------ the host's bar (below the panel)
    local bar = { hover = nil, message = nil, tone = MUTED, note = nil, busy = nil, base = nil, buttons = {} }
    local function layout()
        local s = shim.h / 1080
        local y0, y1 = 1036 * s, 1076 * s
        bar.buttons = {
            { key = 'install', label = '写入游戏', x0 = 30 * s, x1 = 250 * s, y0 = y0, y1 = y1, primary=true },
            { key = 'restore', label = 'Restore the game\'s files', x0 = 266 * s, x1 = 486 * s, y0 = y0, y1 = y1 },
            { key = 'theme', label = shim.theme=='dark' and '浅色模式' or '深色模式', x0 = 502 * s, x1 = 638 * s, y0 = y0, y1 = y1 },
        }
        if bar.release then
            local x1 = shim.w - 30 * s
            bar.buttons[#bar.buttons + 1] = { key = 'update', label = 'Update to ' .. bar.release.label, x0 = x1 - 170 * s, x1 = x1,
                               y0 = 9 * s, y1 = 41 * s, gold = true }   -- top right, in the tagline's place
        end
        -- the titles (paint_bar): Stat Editor, then Enemy Editor once the editor offers the switch
        local x = 30 * s
        bar.titles = {}
        for _, t in ipairs({ { 'title_stat', 'SHODAN Stat Editor', GOLD }, { 'title_enemy', 'SHODAN Enemy Editor', RED } }) do
            if t[1] == 'title_stat' or type(state.switch_editor) == 'function' then
                local w = shim.text_width(t[2], 22 * s, true) + 24 * s   -- a box: 12 px each side of the text
                bar.titles[#bar.titles + 1] = { key = t[1], label = t[2], color = t[3], x0 = x, x1 = x + w, y0 = 6 * s, y1 = 42 * s }
                x = x + w + 12 * s
            end
        end
        bar.s, bar.h = s, shim.h
    end
    layout()

    local function toggle_theme()
        shim.set_theme(shim.theme=='dark' and 'light' or 'dark');layout();ARM.invalidate()
        I.mkdirs(I.home)
        local file,why=io.open(THEME,'wb')
        if file then file:write(shim.theme);file:close()
        else bar.message='主题已切换，但无法保存偏好：'..tostring(why);bar.tone=WARN end
    end

    local function installed_count()
        local n = patch and 1 or 0
        for _, v in pairs(ours) do if v then n = n + 1 end end
        return n
    end

    local function status()
        if bar.busy then return bar.busy, WARN end
        if bar.message then return bar.message, bar.tone end
        if state.phase ~= 'ready' then return 'Finding the stats...', MUTED end
        local n = installed_count()
        local dirty = bar.base and state.writes ~= bar.base
        if dirty and n == 0 then return 'Your values are not in the game yet: close the game, then Install.', WARN end
        if dirty then return 'Changed since the last install: Install to put it in the game.', WARN end
        if n > 0 then return 'Your values are installed (' .. n .. ' game files). Close the game before installing.', GOOD end
        return 'The game\'s own files are in place. Close the game, then Install to play with your values.', MUTED
    end

    local function paint_bar()
        local s = bar.s
        shim.fill(0, 1032 * s, shim.w, shim.h, BACK)
        shim.fill(0, 0, shim.w, 46 * s, BACK)
        -- the two editors' titles, as buttons: the one shown bright in a box of its colour, the other dimmed
        -- (brighter under the mouse); a click swaps
        local enemy = type(state.enemy_on) == 'function' and state.enemy_on()
        local function toward_back(c, k)
            return { 255, math.floor(BACK[2] + (c[2] - BACK[2]) * k), math.floor(BACK[3] + (c[3] - BACK[3]) * k),
                     math.floor(BACK[4] + (c[4] - BACK[4]) * k) }
        end
        for _, t in ipairs(bar.titles) do
            local on = (t.key == 'title_enemy') == (enemy and true or false)
            local hovered = bar.hover == t.key and not on
            local c = on and t.color or toward_back(t.color, hovered and 0.65 or 0.4)
            local fill = on and toward_back(t.color, 0.3) or hovered and { 255, 40, 48, 58 } or { 255, 24, 29, 36 }
            local edge = on and t.color or hovered and toward_back(t.color, 0.8) or { 255, 70, 82, 94 }
            local e = math.max(1, math.floor(2 * s + 0.5))
            shim.fill(t.x0, t.y0, t.x1, t.y1, fill)
            shim.fill(t.x0, t.y0, t.x1, t.y0 + e, edge); shim.fill(t.x0, t.y1 - e, t.x1, t.y1, edge)
            shim.fill(t.x0, t.y0, t.x0 + e, t.y1, edge); shim.fill(t.x1 - e, t.y0, t.x1, t.y1, edge)
            shim.flush()
            shim.text(t.label, t.x0 + 12 * s, (t.y0 + t.y1) / 2 + 22 * s * 0.35, 22 * s, c, true)
        end
        local t = tr('OFFLINE  -  edits the game\'s files; they apply when the game starts')
        if not bar.release then
            -- smaller where it would run into the titles (a longer translation)
            local last = bar.titles[#bar.titles]
            local room, size = shim.w - 30 * s - (last and last.x1 + 16 * s or 0), 15 * s
            while size > 10 * s and shim.text_width(t, size) > room do size = size - 0.5 * s end
            shim.text(t, shim.w - 30 * s - shim.text_width(t, size), 31 * s, size, MUTED)
        end
        for _, b in ipairs(bar.buttons) do
            local hovered = bar.hover == b.key and not bar.busy
            shim.fill(b.x0, b.y0, b.x1, b.y1, hovered and { 255, 213, 233, 218 } or { 255, 247, 250, 245 })
            local edge = (hovered or b.primary) and GOLD or { 255, 183, 199, 188 }
            local e = math.max(1, math.floor(2 * s + 0.5))
            shim.fill(b.x0, b.y0, b.x1, b.y0 + e, edge); shim.fill(b.x0, b.y1 - e, b.x1, b.y1, edge)
            shim.fill(b.x0, b.y0, b.x0 + e, b.y1, edge); shim.fill(b.x1 - e, b.y0, b.x1, b.y1, edge)
            shim.flush()
            local size, label = 16 * s, tr(b.label)
            while size > 10 * s and shim.text_width(label, size) > b.x1 - b.x0 - 12 * s do size = size - 0.5 end
            shim.text(label, (b.x0 + b.x1 - shim.text_width(label, size)) / 2, (b.y0 + b.y1) / 2 + size * 0.35, size,
                      (b.gold or b.primary) and GOLD or WHITE,b.primary)
        end
        local text, tone = status()
        text = tr(text)
        if bar.note then text = text .. ' ' .. tr(bar.note) end
        if not bar.busy and not bar.message then text = (bar.base and state.writes ~= bar.base) and '有未写入修改' or '编辑器已就绪' end
        local x = 662 * s
        local size = 14 * s
        local limit = shim.w - 30 * s - x
        while size > 9 * s and shim.text_width(text, size) > limit do size = size - 0.5 end
        shim.text(text, x, 1055 * s + size * 0.35, size, tone)
    end

    local function paint()
        if eui then return end
        if state.phase == 'ready' then
            if AR.is_open() then ARM.frame(shim) else shim.paint_guis(BACK) end
        else
            shim.fill(0, 0, shim.w, shim.h, BACK)
            centred(tr('Finding the stats...'), shim.h * 0.45, 30 * bar.s, GOLD)
            centred(tostring(state.status or ''), shim.h * 0.45 + 40 * bar.s, 18 * bar.s, MUTED)
        end
        local provider=AR.is_open() and ARM.effects or state.desktop_effects
        if provider then shim.effects(provider()) end
        shim.progress=bar.busy~=nil
        paint_bar()
        shim.present()
    end

    local function say(text, tone, note) bar.message, bar.tone, bar.note = text, tone or MUTED, note end

    local function busy(text)
        bar.busy = text
        if eui and type(rawget(_G,'SHODAN_EUI_PROGRESS'))=='function' then
            local done,total=text:match('%((%d+) of (%d+)%)')
            SHODAN_EUI_PROGRESS(tr(text),tonumber(done) or 0,tonumber(total) or 0)
        end
        paint()
        shim.pump()
    end

    -- ------------------------------------------------------------ install / restore
    local write_succeeded=false
    local function install()
        local corpse_error=corpses and corpses:validate()
        if corpse_error then say(corpse_error,WARN);return end
        local extra_error=state.desktop and state.desktop.extra_validate and state.desktop.extra_validate()
        if extra_error then say(extra_error,WARN);return end
        if not ARM.flush() then say('请先修正护甲数值输入。',WARN);return end
        if state.desktop_commit and not state.desktop_commit() then say('请输入有效数值，再写入游戏。',WARN);return end
        if I.game_running() then say('Helldivers 2 is running: close it, then Install.', WARN); return end
        busy('Installing: finding what changed...')
        local dropped=state.load_donors and state.load_donors() or 0
        local changes, problems = D.diff()
        if corpses then corpses:include_change(changes)end
        if problems and #problems > 0 then
            for _, c in ipairs(changes) do G.free(c.plain) end
            bar.busy = nil
            local first = problems[1]
            log('install stopped: ' .. first.name .. ': ' .. tostring(first.why))
            say('Not installed: ' .. first.name .. ' could not be read (' .. tostring(first.why)
                .. '). Nothing was changed.', WARN)
            return
        end
        -- the Armor page's choices on top of the panel's own passive page: one writer, one hash correction
        local stacks, own_off, policy = AR.selection(state.stacks and state.stacks() or {},
                                                     state.own_off and state.own_off() or {}, D.passives())
        local stacked, why_not = D.stack(changes, stacks, log, own_off, policy)
        if stacked then stacked,why_not=D.armor_passives(changes,state.armor_passives and state.armor_passives(),log,state.one_line and state.one_line())end
        if not stacked then
            for _, c in ipairs(changes) do G.free(c.plain) end
            bar.busy = nil
            log('install stopped: passive stacking: ' .. tostring(why_not))
            say('Not installed: the armor passives could not be stacked (' .. tostring(why_not) .. '). Nothing was changed.', WARN)
            return
        end
        local coded
        coded, why_not = D.codes(changes, state.codes and state.codes(), log)
        if not coded then
            for _, c in ipairs(changes) do G.free(c.plain) end
            bar.busy = nil
            log('install stopped: stratagem codes: ' .. tostring(why_not))
            say('Not installed: the stratagem codes could not be set (' .. tostring(why_not) .. '). Nothing was changed.', WARN)
            return
        end
        -- Stacking can add an armor file to the write plan even when none of
        -- its scalar fields changed, so protect managed files after that step.
        if not mod_management_enabled then
            for _,c in ipairs(changes)do if managed[c.name]then
                for _,prepared in ipairs(changes)do G.free(prepared.plain)end
                bar.busy=nil;say('未写入：'..c.name..' 正由已安装的 Mod 使用。当前未开启 Mod 功能，为保留它的内容，请先开启 Mod 管理再修改此文件。',WARN);return
            end end
        end
        local writes, made, back, nudged = {}, 0, 0, 0
        for k, c in ipairs(changes) do
            busy(string.format('Installing: preparing %s (%d of %d)...', c.name, k, #changes))
            local sealed, why = D.build(c, function(text) log(c.name .. ': ' .. text); shim.pump() end)
            if not sealed then
                for j = k + 1, #changes do G.free(changes[j].plain) end
                bar.busy = nil
                log('install stopped: ' .. c.name .. ': ' .. tostring(why))
                say('Not installed: ' .. c.name .. ' could not be prepared (' .. tostring(why) .. '). Nothing was changed.', WARN)
                return
            end
            writes[c.name], made = sealed, made + 1
            if c.borrowed and #c.borrowed > 0 then nudged = nudged + 1 end
        end
        -- Always rebuild the enabled overlay against immutable originals. Never
        -- merge a previous installation back into the next installation.
        local next_managed={}
        local ok_merge,merge_error=pcall(function()
            for name,inputs in pairs(mod_management_enabled and managed_inputs or {}) do
                local base,n=G.open_sealed(assert(originals[name],'没有可信原版：'..name))
                assert(base,n);local baseline=ffi.string(base,n);G.free(base)
                local all={};for _,input in ipairs(inputs) do all[#all+1]=input end
                if writes[name] then all[#all+1]={label='编辑器当前修改',data=writes[name]} end
                local merged=require('mod_merge').merge(baseline,all,'abort')
                if merged.blocked then
                    local first=merged.conflicts[1]
                    error(name..'：'..merged.conflict_count..' 处冲突；'..first.before..' 与 '..first.after..'，偏移 '..first.offset)
                end
                writes[name]=merged.data;next_managed[name]=true
            end
        end)
        if not ok_merge then bar.busy=nil;say('未写入：'..tostring(merge_error),WARN);return end
        for name, mine in pairs(ours) do
            if mine and not writes[name] and (mod_management_enabled or not managed[name]) then writes[name], back = originals[name], back + 1 end
        end
        if mod_management_enabled then for name in pairs(managed) do if not writes[name] then writes[name]=assert(originals[name]) end end end
        local physics, vehicles = nil, nil
        if rawget(_G, 'SHODAN_PHYSICS') then physics, vehicles = V.patch() end
        if not next(writes) and not physics and not patch then
            bar.busy, bar.base = nil, state.writes
            write_succeeded=true
            say('Nothing to install: your values are the game\'s own.', GOOD)
            return
        end
        made=0;for name,data in pairs(writes) do if data~=originals[name] then made=made+1 end end
        busy('Installing: writing the files...')
        local pending={};for name in pairs(next_managed) do pending[name]=true end
        for name in pairs(managed) do pending[name]=true end
        if mod_management_enabled then
        I.mkdirs(I.home)
        local marker,marker_error=io.open(managed_path,'wb')
        if not marker then bar.busy=nil;say('未写入：无法保存 Mod 安装记录：'..tostring(marker_error),WARN);return end
        local marked={};for name in pairs(pending) do marked[#marked+1]=name end;table.sort(marked)
        assert(marker:write(table.concat(marked,'\n')));assert(marker:close())
        end
        local done, why = true, nil
        if next(writes) then done, why = I.write_files(game, writes, originals, false, observed) end
        if done then for name, data in pairs(writes) do ours[name] = data ~= originals[name] end end
        if done and (physics or patch) then
            local name
            done, name = I.write_patch(game, V.BASE, physics)
            if done then
                if physics then made = made + 1 elseif patch then back = back + 1 end
                patch = name
                log(physics and ('vehicle handling: ' .. name .. ' (' .. table.concat(vehicles, ', ') .. ')')
                    or 'vehicle handling: patch removed')
            else
                why = name
            end
        end
        bar.busy = nil
        if not done then
            log('install failed: ' .. tostring(why))
            say('Not installed: ' .. tostring(why), WARN)
            return
        end
        for name, data in pairs(writes) do ours[name] = data ~= originals[name] end
        write_succeeded=true
        if mod_management_enabled then
        managed=next_managed
        local marker=io.open(managed_path,'wb');local names={}
        for name in pairs(managed) do names[#names+1]=name end;table.sort(names)
        if marker then marker:write(table.concat(names,'\n'));marker:close() end
        end
        bar.base = state.writes
        local armor = AR.touches() and ('  ' .. AR.summary()) or ''
        log(string.format('installed: %d changed, %d back to the original, %d had a decimal value borrowed for the hash',
            made, back, nudged))
        say(string.format('Installed (%d game files changed%s). Start the game to play with your values.', made,
            back > 0 and ', ' .. back .. ' back to the original' or '') .. armor, GOOD,
            nudged > 0 and 'A file of one block has no spare header room, so one decimal value in it moved a few units'
                .. ' in the last place: that is how it keeps the hash the game knows.' or nil)
    end

    local function restore()
        if I.game_running() then say('Helldivers 2 is running: close it, then restore.', WARN); return end
        local writes = {}
        for name, mine in pairs(ours) do if mine and (mod_management_enabled or not managed[name]) then writes[name] = originals[name] end end
        for name,data in pairs(shipped or {}) do if mod_management_enabled or not managed[name] then writes[name]=data end end
        if not next(writes) and not patch then write_succeeded=true;say('The game\'s own files are already in place.', GOOD); return end
        busy('Restoring the game\'s files...')
        local names = {}
        for name in pairs(writes) do names[#names + 1] = name end
        local done, why = I.write_files(game, writes, originals, true, observed)
        if done and patch then
            local removed, problem = I.write_patch(game, V.BASE, nil)
            if removed then patch = nil; log('vehicle handling: patch removed') else done, why = nil, problem end
        end
        bar.busy = nil
        if not done then say('Not restored: ' .. tostring(why), WARN); return end
        write_succeeded=true
        -- files another tool changed since: left as they are (theirs now); files another mod had changed before
        -- this editor: back to that mod's version, which Steam's file check replaces (issue #90)
        local modded = 0
        for _, name in ipairs(names) do
            ours[name] = false
            if writes[name] and D.modded[name] then modded = modded + 1 end
        end
        for _, name in ipairs(why) do log('restore skipped ' .. name .. ': another tool changed it since') end
        bar.base = nil
        log('restored the originals')
        say('The game\'s files are back as they were before this editor. Your values stay saved here (Install puts them in again).'
            .. (modded > 0 and string.format(' %d of them still hold another mod\'s changes: Steam\'s "Verify integrity of game files" puts back the game\'s own.', modded) or ''), GOOD)
    end

    local function dispatch(action)
        write_succeeded=false
        bar.message,bar.note=nil,nil
        log('clicked: '..action)
        local ok,why=pcall(action=='install' and install or restore)
        if not ok then bar.busy=nil;say('操作失败：'..tostring(why),WARN);log('action failed: '..tostring(why)) end
        ARM.invalidate()
        paint()
        if not qa_output and bar.message then shim.message_box(tr(bar.message),bar.tone==WARN and 0x30 or 0x40) end
        return bar.message
    end

    if eui then
        local started=clock()
        repeat
            update(0.05)
            assert(state.phase~='gave_up','数据读取失败：'..tostring(state.status))
            assert(state.phase=='ready' or clock()-started<30,'读取数据超时（'..tostring(state.phase)..'）：'..tostring(state.status))
        until state.phase=='ready'
        -- Apply queued saved values before exposing the model.
        for _=1,10 do update(0.05) end
        bar.base=state.writes or 0
        ARM.load_values()
        local B=state.desktop
        corpses=require('corpse_cleanup').attach(B,D,I,function()state.writes=(state.writes or 0)+1 end)
        B.game=game;B.armor_list=AR.list;B.armor_groups=AR.groups
        B.armor_rows=D.armor_values
        require('armor_presets').attach(B,D,ARM,AR)
        B.armor_set=function(pid,key,value)
            local old;for _,r in ipairs(D.armor_values(pid))do if r.key==key then old=r.value;break end end
            assert(old~=nil,'找不到护甲参数')
            local result,why=ARM.set_value(pid,key,value);assert(result~=nil,why)
            if result~=old then B._record_edit('护甲被动 #'..pid..' · '..key,old,result,function(target,expected)
                for _,r in ipairs(D.armor_values(pid))do if r.key==key then assert(r.value==expected,'护甲数值已被其他操作改变，无法安全撤销')end end
                local applied,err=ARM.set_value(pid,key,target);assert(applied~=nil,err)
            end)end
            return result
        end
        B.armor_profile=function(id) return AR.group(id) end
        B.armor_update=function(target,id,enabled,own,policy)
            local p=AR.group(target)
            local old={enabled={},own=p.own,conflicts=p.conflicts,configured=p.configured}
            for k,v in pairs(p.enabled) do old.enabled[k]=v end
            if id then p.enabled[id]=enabled or nil end
            if own~=nil then p.own=own end
            if policy then p.conflicts=policy end
            p.configured=true;AR.dirty=true
            if AR.save()==false then AR.profiles[target]=old;error('护甲配置保存失败') end
            local after={enabled={},own=p.own,conflicts=p.conflicts,configured=p.configured}
            for k,v in pairs(p.enabled)do after.enabled[k]=v end
            local function equal(a,b)
                if a.own~=b.own or a.conflicts~=b.conflicts or a.configured~=b.configured then return false end
                for k,v in pairs(a.enabled)do if b.enabled[k]~=v then return false end end
                for k,v in pairs(b.enabled)do if a.enabled[k]~=v then return false end end;return true
            end
            if not equal(old,after)then B._record_edit('护甲组合 · '..target,old,after,function(value,expected)
                local current=AR.group(target);assert(equal(current,expected),'护甲组合已被其他操作改变，无法安全撤销')
                local copy={enabled={},own=value.own,conflicts=value.conflicts,configured=value.configured}
                for k,v in pairs(value.enabled)do copy.enabled[k]=v end
                AR.profiles[target]=copy;AR.dirty=true
                if AR.save()==false then AR.profiles[target]=current;error('护甲配置保存失败')end
                state.writes=(state.writes or 0)+1
            end)end
            state.writes=(state.writes or 0)+1;return true
        end
        B.install_preview=function()
            local extra_error,extra_warnings
            if B.extra_validate then extra_error,extra_warnings=B.extra_validate() end
            extra_error=extra_error or (corpses and corpses:validate())
            assert(not extra_error,extra_error)
            local entries=B.pending_preview()
            for _,a in ipairs(AR.list) do
                for _,r in ipairs(D.armor_values(a.id)) do
                    if r.value~=r.default then entries[#entries+1]={equipment=a.zh,parameter=r.label,
                        before=tostring(r.default),after=tostring(r.value),file=AR.FILE} end
                end
            end
            for id,p in pairs(AR.profiles) do
                if p.configured then
                    local enabled={};for _,a in ipairs(AR.list) do if p.enabled[a.id] then enabled[#enabled+1]=a.zh end end
                    if #enabled>0 or p.own==false then
                        entries[#entries+1]={equipment='护甲被动组合',parameter=id==999 and '所有护甲' or ('被动 #'..id),
                            before='游戏原有被动',after=(p.own==false and '移除原生；' or '保留原生；')..table.concat(enabled,'、')..
                                (p.conflicts=='strongest' and '；同类保留最强' or '；同类叠加'),file=AR.FILE}
                    end
                end
            end
            local dropped=state.load_donors and state.load_donors() or 0
            if dropped>0 then extra_warnings=extra_warnings or {};extra_warnings[#extra_warnings+1]=tostring(dropped).." 项资源超过载入上限，可能缺少射弹轨迹或无法始终携带。"end
            local changes,problems=D.diff()
            if corpses then corpses:include_change(changes)end
            local ok,why=pcall(function()
                local stacks,off,policy=AR.selection(state.stacks and state.stacks() or {},state.own_off and state.own_off() or {},D.passives())
                local stacked,reason=D.stack(changes,stacks,log,off,policy);assert(stacked,reason)
                local combined,reason=D.armor_passives(changes,state.armor_passives and state.armor_passives(),log,state.one_line and state.one_line());assert(combined,reason)
                local coded,reason=D.codes(changes,state.codes and state.codes(),log);assert(coded,reason)
            end)
            local files={};for _,c in ipairs(changes) do files[#files+1]=c.name;G.free(c.plain) end
            local errors={};for _,p in ipairs(problems) do errors[#errors+1]=p.name..': '..tostring(p.why) end
            if not ok then errors[#errors+1]=tostring(why) end
            for name,inputs in pairs(mod_management_enabled and managed_inputs or {}) do
                local found=false;for _,f in ipairs(files) do if f==name then found=true end end
                if not found then files[#files+1]=name end
                for _,input in ipairs(inputs) do entries[#entries+1]={equipment=input.label,parameter='已开启 Mod',before='原版基准',after='合并后写入',file=name} end
            end
            for name in pairs(mod_management_enabled and managed or {}) do
                local found=false;for _,f in ipairs(files) do if f==name then found=true end end
                if not found then files[#files+1]=name end
            end
            local patch_bytes=V.shared and V.patch()
            if patch_bytes then files[#files+1]='载具、动作与游戏文字资源补丁' end
            table.sort(files)
            if not mod_management_enabled then for _,name in ipairs(files)do if managed[name]then errors[#errors+1]=name..' 正由已安装的 Mod 使用；请开启 Mod 管理后再修改此文件。' end end end
            return {name='写入游戏预览',entries=entries,files=files,problems=errors,warnings=extra_warnings or {},count=#entries}
        end
        B.managed_mods=function(inputs)
            local grouped={}
            for _,entry in ipairs(inputs or {}) do
                assert(type(entry.name)=='string' and originals[entry.name],'不支持或没有可信原版：'..tostring(entry.name))
                assert(type(entry.data)=='string','Mod 数据无效')
                grouped[entry.name]=grouped[entry.name] or {}
                grouped[entry.name][#grouped[entry.name]+1]={label=entry.label,data=entry.data}
            end
            managed_inputs=grouped;return true
        end
        B.mod_management=function(enabled)
            assert(type(enabled)=='boolean','Mod 管理开关必须为布尔值')
            mod_management_enabled=enabled;return enabled
        end
        B.game_running=function() return I.game_running() end
        B.write_succeeded=function() return write_succeeded end
        B.install=function() return tr(dispatch('install')) end
        B.install_task=function()
            local message=tr(dispatch('install'))
            return {ok=write_succeeded,message=message or ''}
        end
        B.restore=function() return tr(dispatch('restore')) end
        B.merge_named=function(name,inputs)
            local p,n=G.open_sealed(assert(originals[name],'没有可信原版：'..tostring(name)))
            assert(p,n);local base=ffi.string(p,n);G.free(p)
            local result=require('mod_merge').merge(base,inputs,'abort')
            if result.blocked then
                local first=result.conflicts[1]
                error(name..'：'..result.conflict_count..' 处冲突；'..first.before..' 与 '..first.after..'，偏移 '..first.offset)
            end
            return result
        end
        B.merge_mods=function(base,inputs,policy)return require('mod_merge').merge(base,inputs,policy)end
        B.tick=function() update(0.05) end
        B.status=function() return {phase=state.phase,writes=state.writes or 0,dirty=bar.base~=state.writes,
            weapons=state.weapons,stratagems=state.stratagems,vehicles=state.vehicles,
            attachments=state.attachments,tables=state.tables,warning=log_eui_warning} end
        return B
    end

    -- ------------------------------------------------------------ updates (update.lua)
    local exe_dir = exe_dir
    local function update_program()
        local release = bar.release
        busy('Updating: downloading ' .. release.label .. '...')
        local zip = U.dir .. '/' .. release.name
        local job, why = U.fetch(release.url, zip)
        local done = nil
        if job then
            repeat
                if not shim.pump() then bar.busy = nil; return false end
                shim.sleep(20)
                done, why = U.poll(job)
            until done ~= nil
        end
        if not done then
            bar.busy = nil
            log('update: download failed: ' .. tostring(why))
            say('Update failed: ' .. tostring(why) .. '. The release page has it: ' .. U.PAGE, WARN)
            return false
        end
        busy('Updating: installing ' .. release.label .. '...')
        local exe, problem = U.install(zip, exe_dir, log)
        bar.busy = nil
        if not exe then
            log('update: not installed: ' .. tostring(problem))
            say('Update failed: ' .. tostring(problem) .. '. Nothing was changed.', WARN)
            return false
        end
        log('update: ' .. release.label .. ' installed, restarting: ' .. exe)
        U.note(release.label)
        bar.restart = exe
        return true
    end

    -- ------------------------------------------------------------ the frame loop
    local painted, was_down, was_f5, armed, said_ready = nil, false, false, nil, false
    local last = clock()
    local qa_ready_frames = 0
    local last_paint=0
    local loading_started = clock()
    while shim.pump() do
        local now = clock()
        update(math.min(0.1, now - last))
        last = now
        if state.phase == 'gave_up' then fatal('数据读取失败：' .. tostring(state.status)) end
        if state.phase ~= 'ready' and now-loading_started > 30 then fatal('读取超过 30 秒：'..tostring(state.status)..'\n请查看 Logs 目录中的日志。') end
        if bar.h ~= shim.h then layout() end   -- moved onto another screen: sized for that one
        if state.phase == 'ready' and not said_ready then
            said_ready = true
            bar.base = state.writes or 0
            ARM.load_values()
            log(string.format('ready: %s weapons, %s values applied, %s refused', tostring(state.weapons),
                tostring(state.applied), tostring(state.refused)))
            local stacks = state.stacks and state.stacks() or {}
            local own_off = state.own_off and state.own_off() or {}
            if installed_count() == 0 and ((state.applied or 0) > 0 or next(stacks) or next(own_off)) then bar.base = -1 end
            if I.game_running() then say('Helldivers 2 is running: you can edit, but close it before you Install.', WARN) end
            if #(I.compat_warnings or {})>0 then say('旧版备份已保留；迁移目录不可写，写入游戏前仍需解决备份权限。',WARN) end
            local updated = U.cleanup()
            if updated then say('Updated to ' .. updated .. '.', GOOD) end
        end
        -- updates: asked at start, and again when Settings > Update channel changes
        local channel = type(state.update_channel) == 'function' and state.update_channel() or 'releases'
        if said_ready and U.available and channel ~= bar.channel and not U.checking and not bar.restart then
            bar.channel = channel
            if bar.release then bar.release = nil; layout() end
            U.check(channel)
        end
        if U.checking then
            local current = { version = state.version, commit = build.commit }
            local release = U.check_poll(current)
            if release and bar.channel ~= U.channel then release = nil end   -- the channel changed meanwhile
            if release then
                bar.release = release
                layout()
                log('update: ' .. release.label .. ' is available (' .. release.name .. ')')
                -- Settings > Updates: Automatic
                if type(state.updates) == 'function' and state.updates() == 'auto' and update_program() then break end
            elseif release == false then
                log('update: nothing newer on ' .. tostring(U.channel) .. ' than v' .. tostring(current.version)
                    .. (current.commit and ' (' .. current.commit:sub(1, 7) .. ')' or ''))
            end
        end
        -- the bar's buttons
        -- F5 opens the armor page: it draws instead of the panel, and parks the panel's tick while it is up
        local f5 = state.phase == 'ready' and shim.focused() and shim.key_down(0x74) or false
        if f5 and not was_f5 then
            if AR.is_open() then AR.close() else AR.show() end
            painted = nil
        end
        was_f5 = f5
        local x, y = nil, nil
        if shim.focused() then x, y = shim.cursor() end
        local hover = nil
        for _, b in ipairs(bar.buttons) do
            if x and x >= b.x0 and x < b.x1 and y >= b.y0 and y < b.y1 then hover = b.key end
        end
        if #bar.titles > 1 then
            for _, b in ipairs(bar.titles) do
                if x and x >= b.x0 and x < b.x1 and y >= b.y0 and y < b.y1 then hover = b.key end
            end
        end
        bar.hover = hover
        local down = shim.focused() and shim.key_down(0x01)
        if down and not was_down then armed = hover end
        if not down and was_down and armed and armed == hover and state.phase == 'ready' then
            bar.message = nil
            if hover == 'install' or hover == 'restore' then dispatch(hover);painted=nil
            elseif hover == 'theme' then toggle_theme();painted=nil
            elseif hover == 'update' and update_program() then break
            elseif hover == 'title_stat' or hover == 'title_enemy' then state.switch_editor(hover == 'title_enemy') end
            armed = nil
        end
        was_down = down
        local text = status()
        local signature = table.concat({ shim.version, state.phase, tostring(state.status), tostring(hover), text,
                                         shim.lang(), bar.release and bar.release.label or '', tostring(bar.note) }, '|')
        if signature ~= painted or (AR.is_open() or shim.animating()) and now-last_paint>=0.033 then
            last_paint=now
            painted = signature
            paint()
        end
        if qa_output and state.phase == 'ready' then
            qa_ready_frames = qa_ready_frames + 1
            if qa_ready_frames >= 30 and (shim.draw_items or 0) > 30 then
                paint()
                shim.save_bmp(qa_output .. '/full-editor.bmp')
                local qa = assert(state.qa_ui, 'UI test driver unavailable')
                assert(qa.desktop_layout_regression(),'desktop layout regression failed')
                local baseline_rows,baseline_resets,installed_values=qa.baseline_regression(os.getenv('SHODAN_QA_INSTALLED')=='1')
                assert(baseline_rows>10000 and baseline_resets>20,'initial values regression did not cover the data pages')
                log(string.format('initial values: %d rows checked, %d input/reset paths restored, %d installed values differ from originals',baseline_rows,baseline_resets,installed_values))
                local inventory=assert(io.open(qa_output..'/parameter-labels.tsv','wb'))
                for _,row in ipairs(qa.label_inventory()) do inventory:write(table.concat(row,'\t'),'\n') end
                inventory:close()
                local translations=assert(io.open(qa_output..'/translations.tsv','wb'))
                local translated_items=qa.translation_inventory()
                for _,row in ipairs(translated_items) do
                    assert(row[2]~=row[3] or not row[2]:find('%a%a%a'),'untranslated '..row[1]..': '..row[2])
                    for k,v in ipairs(row) do row[k]=tostring(v):gsub('[\r\n\t]',' ') end
                    translations:write(table.concat(row,'\t'),'\n')
                end
                translations:close()
                local records,reloads=qa.release_regression();assert(records==2 and reloads>=1,'3.2.3 release regression failed')
                assert(state.tr('Durable damage')=='耐久伤害' and state.tr('Blast proximity (m)')=='近炸引信半径（米）','parameter terminology mismatch')
                local saved_weapon=qa.current()
                for _,tab in ipairs({'Primary','Stratagems','Records'}) do
                    qa.navigate(tab);qa.redraw()
                    local page,total,scrollbar,active=qa.left_state()
                    assert(active==tab and page==1 and not scrollbar,'left list is not a fixed page')
                    qa.left_wheel(-8);qa.redraw()
                    assert(qa.left_state()==1,'left wheel changed the page')
                    local rows=qa.list_rows()
                    if total>rows then
                        qa.page_next();qa.redraw();assert(qa.left_state()==rows+1,'next page did not start after the current page')
                        qa.left_wheel(8);qa.redraw();assert(qa.left_state()==rows+1,'left wheel changed second page')
                        qa.page_prev();qa.redraw();assert(qa.left_state()==1,'previous page failed')
                    end
                end
                qa.select(saved_weapon.hash)
                qa.redraw();assert(qa.no_feature_shortcuts(),'redundant feature shortcut still visible')
                qa.redraw();paint();shim.save_bmp(qa_output..'/feature-entries.bmp')
                local features=qa.upstream_features()
                assert(features.status>100 and features.extra>50 and features.regen>=10 and features.callin>50 and features.eagle>0,'official 3.2.0 fields missing')
                assert(qa.test_choice('status'),'status selector failed')
                assert(qa.test_choice('stratagem'),'extra stratagem selector failed')
                -- Back up and write only a synthetic file under the isolated QA folder.
                local fake=qa_output..'/fake-game';I.mkdirs(fake)
                local filename='generated_qa_backup.dl_bin'
                local f=assert(io.open(fake..'/'..filename,'wb'));f:write('QA original');f:close()
                local running=I.game_running;I.game_running=function() return false end
                local written,why=I.write_files(fake,{[filename]='QA modified'},{[filename]='QA original'})
                assert(written,why)
                local backups=I.originals(fake);assert(backups[filename]=='QA original','official backup missing')
                -- Old indexed backups migrate before the official reader is used.
                local original='QA original'
                local hash=G.hex64(G.murmur64(ffi.cast('const uint8_t *',original),#original))
                I.mkdirs(I.home..'/backups')
                local relative='backups/'..hash..'_'..filename
                local prior=assert(io.open(I.home..'/'..relative,'wb'));prior:write(original);prior:close()
                local index=assert(io.open(I.home..'/backup-index.txt','wb'));index:write(filename..' '..relative..'\n');index:close()
                assert(os.remove(I.originals_dir..'/'..filename))
                local migrated,migration_error=I.migrate_compat_backups(fake);assert(migrated==1,migration_error)
                backups=I.originals(fake);assert(backups[filename]==original,'migrated original not restored')
                local previous_originals_dir=I.originals_dir
                I.originals_dir=qa_output..'/blocked-originals'
                local occupied=assert(io.open(I.originals_dir,'wb'));occupied:write('file occupies the directory');occupied:close()
                local count,why=I.migrate_compat_backups(fake)
                assert(count==0 and I.compat_originals[filename]==original and #I.compat_warnings==1,'read-only migration fallback failed')
                assert(I.read(I.home..'/'..relative)==original,'legacy backup was lost')
                I.originals_dir=previous_originals_dir;I.compat_originals={};I.compat_warnings={}
                I.game_running=running
                local text_input=require('text_input')
                qa.search_open();text_input.push(string.byte('A'));text_input.push(string.byte('R'))
                qa.text_events(shim.take_text());local entered,active,matches=qa.search_state()
                assert(entered=='AR' and active and matches>0,'English search input failed')
                qa.search_clear();qa.search_open()
                for _,code in ipairs({0x89E3,0x653E,0x8005}) do text_input.push(code) end
                qa.text_events(shim.take_text());entered,active,matches=qa.search_state()
                assert(entered=='解放者' and matches>0,'Chinese search input failed')
                qa.redraw();paint();shim.save_bmp(qa_output..'/search.bmp')
                qa.search_clear()
                -- Test install feedback using stubbed dependencies; never write game files.
                local running,diff,stack,write,buildfn=I.game_running,D.diff,D.stack,I.write_files,D.build
                local saved_ours=ours;ours={}
                I.game_running=function() return true end
                assert(dispatch('install'):find('running',1,true),'blocked install feedback missing')
                I.game_running=function() return false end
                D.diff=function() return {} end;D.stack=function() return true end
                assert(dispatch('install'):find('Nothing to install',1,true),'unchanged install feedback missing')
                D.diff=function() return {{name='qa-only.dl_bin'}} end
                D.build=function() return 'memory-only' end
                I.write_files=function() return nil,'QA simulated write failure' end
                assert(dispatch('install'):find('QA simulated write failure',1,true),'write failure feedback missing')
                I.write_files=function() return true end
                assert(dispatch('install'):find('Installed',1,true),'success feedback missing')
                I.game_running,D.diff,D.stack,I.write_files,D.build=running,diff,stack,write,buildfn
                ours=saved_ours;bar.message=nil;bar.note=nil
                local before = qa.current().rows[1]
                local original = qa.value_current(1)
                -- Read through the same UI controller that handles direct input.
                local old = qa.value(1, 1234)
                assert(old == 1234, 'custom numeric input did not apply')
                qa.redraw();paint();shim.save_bmp(qa_output..'/changed-values.bmp')
                qa.value(1, original)
                shim.transition()
                for frame=1,4 do shim.capture_path=qa_output..'/motion-'..frame..'.bmp';paint();shim.sleep(90) end
                qa.select('80F1A156D9FA1E36') -- JAR-5: verify the reported weapon, independent of the last selected tab.
                local old_ammo = qa.ammo_current()
                assert(qa.ammo_open(), 'ammo picker did not open')
                local choices = qa.ammo_rows()
                assert(#choices > 20, 'ammo names were not enumerated')
                qa.redraw();paint();shim.save_bmp(qa_output .. '/ammo-picker.bmp')
                local selected
                for _, item in ipairs(choices) do if item.id ~= old_ammo then selected=item;break end end
                assert(selected and qa.ammo_choose(selected.id), 'ammo name selection failed')
                assert(qa.ammo_current() == selected.id, 'selected ammo was not applied')
                assert(qa.ammo_open() and qa.ammo_choose(old_ammo), 'ammo restore failed')
                local previous_weapon=qa.current().hash
                toggle_theme();assert(shim.theme=='dark')
                assert(qa.open_status_popup(),'status popup unavailable')
                qa.redraw();paint();shim.save_bmp(qa_output..'/dark-status-popup.bmp')
                local scale=shim.h/1080;local px,py=math.floor(60*scale),math.floor(55*scale)
                assert(shim.bits[py*shim.w+px]==0,'modal backdrop is not pure black')
                qa.close_popup();qa.select(previous_weapon);toggle_theme();qa.redraw()
                AR.show();ARM.action('toggle:1');ARM.action('toggle:7')
                assert(AR.group(999).enabled[1] and AR.group(999).enabled[7], 'multi-passive selection failed')
                ARM.frame(shim);paint_bar();shim.save_bmp(qa_output .. '/armor-main.bmp')
                toggle_theme();assert(shim.theme=='dark');paint();shim.save_bmp(qa_output..'/dark-armor.bmp')
                toggle_theme();assert(shim.theme=='light');paint()
                ARM.secondary(1)
                local effect=assert(D.armor_values(1)[1])
                local changed, why=ARM.set_value(1,effect.key,effect.value+0.25)
                assert(changed~=nil,why)
                ARM.frame(shim);paint_bar();shim.save_bmp(qa_output .. '/armor-values.bmp')
                local function preflight(stacking)
                    local dropped=state.load_donors and state.load_donors() or 0
            if dropped>0 then extra_warnings=extra_warnings or {};extra_warnings[#extra_warnings+1]=tostring(dropped).." 项资源超过载入上限，可能缺少射弹轨迹或无法始终携带。"end
            local changes,problems=D.diff();assert(#problems==0,'diff failed')
                    if stacking then
                        local stacks,own_off,policy=AR.selection({}, {}, D.passives())
                        local ok,why=D.stack(changes,stacks,log,own_off,policy);assert(ok,why)
                    end
                    local count,prepared=0,{}
                    for _,change in ipairs(changes) do
                        if stacking and change.name=='generated_customization_passive_bonuses.dl_bin' then
                            for _,header in ipairs(G.headers(change.plain,change.n)) do
                                if header.type==0x63CE0FEB then
                                    local base=header.at+24;local count=tonumber(ffi.cast('uint32_t *',change.plain+base+24)[0])
                                    local offset=base+tonumber(ffi.cast('uint64_t *',change.plain+base+16)[0])
                                    local seen,described={},0
                                    for i=0,count-1 do
                                        local row=change.plain+offset+i*16
                                        local id=tonumber(ffi.cast('uint32_t *',row)[0]);assert(not seen[id],'duplicate passive modifier');seen[id]=true
                                        if ffi.cast('uint32_t *',row+12)[0]~=0 then described=described+1 end
                                    end
                                    assert(described<=3,'too many armor descriptions')
                                end
                            end
                        end
                        local sealed,why=D.build(change,log);assert(sealed,why)
                        assert(type(sealed)=='string' and #sealed>0,'empty prepared file')
                        prepared[change.name]=sealed
                        count=count+1
                    end
                    assert(count>0,'no armor changes to prepare');return prepared
                end
                preflight(false)
                local armor_writes=preflight(true)
                local armor_folder=qa_output..'/armor-game';I.mkdirs(armor_folder)
                local armor_originals={}
                for name in pairs(armor_writes) do
                    armor_originals[name]=D.files[name].cipher
                    local file=assert(io.open(armor_folder..'/'..name,'wb'));file:write(armor_originals[name]);file:close()
                end
                local previous_running=I.game_running;I.game_running=function() return false end
                local committed,commit_error=I.write_files(armor_folder,armor_writes,armor_originals);assert(committed,commit_error)
                for name,sealed in pairs(armor_writes) do assert(I.read(armor_folder..'/'..name)==sealed,'official armor write differs') end
                I.game_running=previous_running


                assert(ARM.set_value(1,effect.key,effect.value)~=nil,'passive reset failed')
                assert(D.armor_defaults_verified,'armor baseline not verified against game.dll')
                local med=D.armor_values(7);assert(#med==2 and med[1].default==2 and med[2].default==2,'medical vanilla defaults differ')
                local fire=D.armor_values(11);assert(fire[1].default==0.25,'fire vanilla default differs')
                local baseline=require('armor_baseline')
                local armor=D.files['generated_customization_passive_bonuses.dl_bin']
                assert(baseline.is_clean(armor.cipher),'editor still uses modified passive baseline')
                local corrupted,n=assert(G.open_sealed(armor.cipher))
                for _,header in ipairs(G.headers(corrupted,n)) do
                    local base=header.at+24
                    if ffi.cast('uint32_t *',corrupted+base)[0]==7 then
                        local at=base+tonumber(ffi.cast('uint64_t *',corrupted+base+16)[0])+8
                        ffi.cast('float *',corrupted+at)[0]=0
                    end
                end
                assert(G.correct(corrupted,n,armor.hash,{},log))
                local modified=G.seal(corrupted,n);G.free(corrupted)
                local repaired,changed,verified=baseline.original(modified,I.read(game..'/game.dll'))
                assert(changed and verified and baseline.is_clean(repaired),'modified backup was accepted as vanilla')
                local refused,changed,verified=baseline.original(modified,'unknown game version')
                assert(refused==modified and not changed and not verified,'unknown version baseline was replaced')
                local stationary=D.armor_values(42);assert(#stationary==2,'Stationary Shroud fields missing')
                local sway
                for _,row in ipairs(stationary) do if row.label=='瞄准晃动倍率' then sway=row end end
                assert(sway and #sway.ats==3,'Stationary Shroud sway fields are not linked')
                assert(ARM.set_value(42,sway.key,sway.value+0.1)~=nil)
                for _,at in ipairs(sway.ats) do assert(math.abs(tonumber(ffi.cast('float *',D.files[AR.FILE].p+at)[0])-sway.value-0.1)<1e-5) end
                assert(ARM.set_value(42,sway.key,sway.value)~=nil)
                ARM.secondary(42);ARM.frame(shim);paint_bar();shim.save_bmp(qa_output..'/stationary-shroud.bmp')

                AR.close()
                local file = assert(io.open(qa_output .. '/report.json', 'wb'))
                local values = {}
                values[#values+1]=string.format('"translation_items":%d,"baseline_rows":%d,"reset_paths":%d,"installed_value_differences":%d,"verified_originals":%d',#translated_items,baseline_rows,baseline_resets,installed_values,shipped_count)
                for _, key in ipairs({ 'weapons', 'stratagems', 'vehicles', 'attachments', 'throwables', 'passives', 'tables', 'ui_errors' }) do
                    values[#values+1] = string.format('"%s":%d', key, tonumber(state[key]) or 0)
                end
                file:write('{"phase":"ready","language":"', state.lang(), '","draw_items":', tostring(shim.draw_items or 0), ',"armor_choices":',tostring(#AR.list),',"ammo_choices":',tostring(#choices),',"unicode_search":true,"install_feedback":true,"custom_input":true,"ammo_selection":true,"armor_value_edit":true,"armor_write_preflight":true,"backup_migration":true,"migration_fallback":true,"core_320_features":true,"theme_switch":true,"fixed_left_pages":true,"no_redundant_shortcuts":true,"pure_black_modal":true,"stationary_shroud":true,"official_write_flow":true,"official_multi_passive_write":true,"vanilla_armor_defaults":true,"release_323_regressions":true,"reviewed_parameters":true,', table.concat(values, ','), '}')
                file:close()
                break
            end
        end
        shim.sleep(state.phase == 'ready' and 10 or 1)
    end
    if shim.place then
        I.mkdirs(I.home)
        local f = io.open(PLACE, 'w')
        if f then f:write(shim.place[1], ' ', shim.place[2], shim.place[3] and (' ' .. shim.place[3]) or '', '\n'); f:close() end
    end
    -- the editor saves its values a moment after a change
    local stop = clock() + 1.5
    while clock() < stop do update(0.05); shim.sleep(20) end
    if bar.restart then
        local go = true
        if go and not U.launch(bar.restart) then
            shim.message_box('Updated. Start ' .. bar.restart:gsub('/', '\\') .. ' again.', 0x40)
        end
    end
    log('closed')
end

local ok, err = xpcall(main, debug.traceback)
if not ok then
    if eui then error(err) end
    log('error: ' .. tostring(err))
    if qa_output then local f=io.open(qa_output..'/failure.txt','wb');if f then f:write(tostring(err));f:close() end;os.exit(1)
    else shim.message_box('SHODAN Stat Editor Offline stopped:\n\n' .. tostring(err), 0x10) end
end

if eui then return err end
