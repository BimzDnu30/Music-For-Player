script_name("MP3 Player GUI")
script_version("1.9 By Bimz")

local imgui = require 'imgui'
local ffi = require 'ffi'
local lfs = require 'lfs'
local encoding = require 'encoding'
local inicfg = require 'inicfg'
local requests = require 'requests'

encoding.default = 'CP1251'
local u8 = encoding.UTF8

--========================================
-- CONFIG
--========================================
local cfg_path = "config/music.cfg"
local default_cfg = {
    settings = {
        volume = 1.0,
        loop = false
    }
}
local cfg = inicfg.load(default_cfg, cfg_path) or default_cfg
inicfg.save(cfg, cfg_path)

local LOCAL_VERSION = "1.9"
local GITHUB_RAW_URL = "https://raw.githubusercontent.com/USERNAME/REPO/main/mp3player.lua"
local VERSION_URL = "https://raw.githubusercontent.com/BimzDnu30/Music-For-Player/main/version.txt"
local SCRIPT_PATH = getWorkingDirectory() .. "/Music.lua"

--========================================
-- GUI
--========================================
imgui.Process = true
local showWindow = imgui.ImBool(false)
local guiUsers = {}

local music_folder = "moonloader/music"
local music_files = {}
local selected_index = 0

--========================================
-- BASS AUDIO
--========================================
ffi.cdef[[
    int BASS_Init(int device, unsigned int freq, unsigned int flags, void *win, void *guid);
    int BASS_Free();
    int BASS_Start();
    int BASS_Stop();
    unsigned int BASS_StreamCreateFile(int mem, const char *file, unsigned long long offset,
        unsigned long long length, unsigned int flags);
    int BASS_ChannelPlay(unsigned int handle, int restart);
    int BASS_ChannelStop(unsigned int handle);
    int BASS_ChannelSetAttribute(unsigned int handle, unsigned int attrib, float value);
    unsigned int BASS_ChannelIsActive(unsigned int handle);
]]

local ok, bass = pcall(ffi.load, "bass.dll")
if not ok then
    sampAddChatMessage("[Music] ERROR: bass.dll tidak ditemukan!", 0xFF0000)
    bass = nil
end

if bass then
    pcall(function()
        bass.BASS_Init(-1, 44100, 0, nil, nil)
        bass.BASS_Start()
    end)
end

local currentStream = nil
local volume = imgui.ImFloat(cfg.settings.volume)
local loopMusic = imgui.ImBool(cfg.settings.loop)

local function updateVolume()
    if bass and currentStream then
        pcall(function()
            bass.BASS_ChannelSetAttribute(currentStream, 2, volume.v)
        end)
    end
end

local function playMP3(path)
    if not bass then return end

    if currentStream then pcall(bass.BASS_ChannelStop, currentStream) end

    local ok, stream = pcall(function()
        return bass.BASS_StreamCreateFile(0, path, 0, 0, 0)
    end)

    if not ok or stream == 0 then
        sampAddChatMessage("[Music] Gagal membuka file: " .. path, 0xFF0000)
        return
    end

    currentStream = stream
    updateVolume()
    pcall(bass.BASS_ChannelPlay, currentStream, 1)
end

local function stopMP3()
    if bass and currentStream then
        pcall(bass.BASS_ChannelStop, currentStream)
    end
end

--========================================
-- SCAN MUSIC FOLDER
--========================================
local function scanMusic()
    music_files = {}

    pcall(function()
        for f in lfs.dir(music_folder) do
            if f ~= "." and f ~= ".." then
                if f:lower():match("%.mp3$") or f:lower():match("%.wav$") or f:lower():match("%.ogg$") then
                    table.insert(music_files, { name = f, path = music_folder .. "/" .. f })
                end
            end
        end
    end)

    table.sort(music_files, function(a, b)
        return a.name:lower() < b.name:lower()
    end)

    selected_index = (#music_files > 0) and 1 or 0
end

--========================================
-- LOOP MUSIC CHECK
--========================================
local lastLoopCheck = os.clock()

local function checkLoopMusic()
    if not (bass and currentStream and loopMusic.v) then return end

    if os.clock() - lastLoopCheck >= 0.5 then
        lastLoopCheck = os.clock()

        local ok, state = pcall(bass.BASS_ChannelIsActive, currentStream)
        if ok and state == 0 then
            pcall(bass.BASS_ChannelPlay, currentStream, 1)
        end
    end
end

--========================================
-- AUTO NEXT MUSIC
--========================================
local function autoNextMusic()
    if not bass or not currentStream then return end
    if loopMusic.v then return end

    local ok, state = pcall(bass.BASS_ChannelIsActive, currentStream)
    if ok and state == 0 then
        if selected_index < #music_files then
            selected_index = selected_index + 1
            local nextTrack = music_files[selected_index]
            playMP3(nextTrack.path)
            sampAddChatMessage("[Music] Next: " .. nextTrack.name, 0x00FF00)
        else
            sampAddChatMessage("[Music] Playlist selesai.", 0xAAAAFF)
        end
    end
end

--========================================
-- UPDATE CURSOR
--========================================
local function updateCursorState()
    imgui.ShowCursor = showWindow.v
end

--========================================
-- AUTO UPDATE GITHUB
--========================================
local function checkUpdate()
    lua_thread.create(function()
        sampAddChatMessage("[Music] Checking updates...", 0xFFFF00)

        local r = requests.get(VERSION_URL)
        if r.status_code ~= 200 then
            sampAddChatMessage("[Music] Gagal cek versi GitHub!", 0xFF0000)
            return
        end

        local latest = r.text:gsub("%s+", "")
        if latest ~= LOCAL_VERSION then
            sampAddChatMessage("[Music] Update tersedia! Versi baru: " .. latest, 0x00FF00)
            sampAddChatMessage("[Music] Mengunduh update...", 0x00FF00)

            local newFile = requests.get(GITHUB_RAW_URL)
            if newFile.status_code == 200 then
                local f = io.open(SCRIPT_PATH, "w")
                f:write(newFile.text)
                f:close()

                sampAddChatMessage("[Music] Update selesai! Restart script...", 0x00FF00)
                thisScript():reload()
            else
                sampAddChatMessage("[Music] Gagal download file!", 0xFF0000)
            end
        else
            sampAddChatMessage("[Music] Kamu sudah versi terbaru.", 0x00FF00)
        end
    end)
end

--========================================
-- GUI WINDOW
--========================================
local function drawMusicGUI()
    imgui.SetNextWindowSize(imgui.ImVec2(460, 520), imgui.Cond.FirstUseEver)
    imgui.Begin("MP3/WAV Player##mp3", showWindow)

    imgui.Text("Folder: " .. music_folder)

    imgui.BeginChild("list", imgui.ImVec2(0, 260), true)
    if #music_files == 0 then
        imgui.Text("No MP3/WAV/OGG found.")
    else
        for i, v in ipairs(music_files) do
            if imgui.Selectable(v.name, i == selected_index) then
                selected_index = i
            end
        end
    end
    imgui.EndChild()

    imgui.Separator()

    if selected_index > 0 and music_files[selected_index] then
        local s = music_files[selected_index]
        imgui.Text("Selected: " .. s.name)

        if imgui.Button("Play") then playMP3(s.path) end
        imgui.SameLine()
        if imgui.Button("Stop") then stopMP3() end
        imgui.SameLine()
        if imgui.Button("Refresh") then scanMusic() end
    end

    imgui.Separator()
    imgui.Text("Volume:")
    if imgui.SliderFloat("##vol", volume, 0.0, 1.0, "%.2f") then
        cfg.settings.volume = volume.v
        inicfg.save(cfg, cfg_path)
        updateVolume()
    end

    imgui.Separator()
    if imgui.Checkbox("Loop Music", loopMusic) then
        cfg.settings.loop = loopMusic.v
        inicfg.save(cfg, cfg_path)
    end

    imgui.Separator()
    imgui.TextColored(imgui.ImVec4(0.8, 0.8, 0.1, 1), "Created by Bimz")

    imgui.End()
end

--========================================
-- IMGUI HOOK
--========================================
local prev = imgui.OnDrawFrame
imgui.OnDrawFrame = function()
    if prev then pcall(prev) end
    updateCursorState()

    if showWindow.v then
        pcall(drawMusicGUI)
    end
end

--========================================
-- COMMAND
--========================================
sampRegisterChatCommand("music", function()
    showWindow.v = not showWindow.v
    guiUsers["You"] = showWindow.v

    if showWindow.v then
        scanMusic()
        sampAddChatMessage("[Music] GUI dibuka.", 0x00FF00)
    else
        sampAddChatMessage("[Music] GUI ditutup.", 0xAAAAFF)
    end
end)

--========================================
-- MAIN LOOP
--========================================
function main()
    while not isSampAvailable() do wait(100) end

    scanMusic()
    sampAddChatMessage("[Music] Loaded v" .. LOCAL_VERSION .. ". /music untuk membuka GUI.", 0x00FFFF)

    checkUpdate()

    while true do
        checkLoopMusic()
        autoNextMusic()
        wait(50)
    end
end

function onScriptTerminate()
    stopMP3()
    if bass then
        pcall(bass.BASS_Stop)
        pcall(bass.BASS_Free)
    end
    imgui.ShowCursor = false
end
