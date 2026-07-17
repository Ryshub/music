local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Re-run: replace any previous instance instead of stacking a duplicate UI.
if _G.MusicTesterCleanup then
	pcall(_G.MusicTesterCleanup)
	_G.MusicTesterCleanup = nil
end

-- ================= Constants =================

local REPO_URL = "https://raw.githubusercontent.com/Ryshub/music/main/"
local LIB_URL = REPO_URL .. "lib.lua"
local TRACKS_URL = REPO_URL .. "tracks.lua"
local ICONS_URL = "https://raw.githubusercontent.com/Footagesus/Icons/main/Main-v2.lua"
local ICON_PACK = "sfsymbols"

local SAVE_DIR = "ryshub/music"
local FAV_FILE = SAVE_DIR .. "/favorites.json"

local COLORS = {
	bar = Color3.fromRGB(16, 16, 18),
	panel = Color3.fromRGB(30, 30, 36),
	field = Color3.fromRGB(44, 44, 52),
	track = Color3.fromRGB(70, 70, 80),
	white = Color3.fromRGB(245, 245, 250),
	icon = Color3.fromRGB(210, 210, 220),
	dim = Color3.fromRGB(140, 140, 150),
	accent = Color3.fromRGB(150, 110, 255),
}

-- ================= Lib bootstrap =================

-- Minimal fetch just to download lib.lua; everything else uses Lib.fetch*.
local function bootstrapFetch(url)
	for _, getter in ipairs({ game.HttpGetAsync, game.HttpGet }) do
		local ok, res = pcall(getter, game, url)
		if ok and type(res) == "string" and res ~= "" then
			return res
		end
	end
	local ok, res = pcall(function()
		return HttpService:GetAsync(url)
	end)
	return ok and res or nil
end

local Lib
do
	local src = bootstrapFetch(LIB_URL)
	if src then
		local ok, mod = pcall(function()
			return loadstring(src)()
		end)
		if ok and type(mod) == "table" then
			Lib = mod
		end
	end
end
if not Lib then
	warn("[music] could not load lib.lua — aborting")
	return
end

local create, corner, padding = Lib.create, Lib.corner, Lib.padding
local createIcon = Lib.icons.createIcon
Lib.icons.configure(ICONS_URL, ICON_PACK)

-- ================= Track data =================

-- Tracks live in tracks.lua; on failure a minimal fallback keeps the UI working.
local musicTracks = {}
do
	local raw = Lib.fetchModule(TRACKS_URL)
	if type(raw) == "table" then
		for _, t in ipairs(raw) do
			if type(t) == "table" and type(t.id) == "string" and t.id ~= "" then
				table.insert(musicTracks, t)
			end
		end
	end
	if #musicTracks == 0 then
		musicTracks = {
			{ genre = "Funk", name = "67 KID FUNK", artist = "DRIFTGØD", id = "84142247103485" },
		}
	end
end

local trackById = {}
local trackIndexById = {}
local searchText = {} -- id -> lowercase "name artist genre" haystack
local genres = {} -- unique genres in order of appearance
do
	local seen = {}
	for i, t in ipairs(musicTracks) do
		trackById[t.id] = t
		trackIndexById[t.id] = i
		searchText[t.id] = ((t.name or "") .. " " .. (t.artist or "") .. " " .. (t.genre or "")):lower()
		if t.genre and not seen[t.genre] then
			seen[t.genre] = true
			table.insert(genres, t.genre)
		end
	end
end

local function trackSubtitle(t)
	if t.artist and t.artist ~= "" then
		return t.artist
	end
	return t.genre or ""
end

-- ================= Favorites (persisted) =================

local favorites = {}

-- Creates ryshub/ and ryshub/music/ if missing (makefolder may not nest).
local function ensureSaveFolder()
	if not (makefolder and isfolder) then
		return
	end
	if not isfolder("ryshub") then
		pcall(makefolder, "ryshub")
	end
	if not isfolder(SAVE_DIR) then
		pcall(makefolder, SAVE_DIR)
	end
end

local function isFavorite(id)
	return table.find(favorites, id) ~= nil
end

local function saveFavorites()
	if writefile then
		ensureSaveFolder()
		pcall(writefile, FAV_FILE, HttpService:JSONEncode(favorites))
	end
end

local function loadFavorites()
	if not (readfile and isfile and isfile(FAV_FILE)) then
		return
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(readfile(FAV_FILE))
	end)
	if ok and type(data) == "table" then
		favorites = data
	end
end

local function toggleFavorite(id)
	local at = table.find(favorites, id)
	if at then
		table.remove(favorites, at)
	else
		table.insert(favorites, id)
	end
	saveFavorites()
end

-- ================= Sound + root UI =================

local sound = create("Sound", {
	Name = "MusicTester",
	Volume = 0.5,
	Looped = false,
	Parent = SoundService,
})

local screenGui = create("ScreenGui", {
	Name = "MusicTesterGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})

-- ================= Main bar =================

local bar = create("Frame", {
	Name = "PlayerBar",
	Size = UDim2.fromOffset(340, 112),
	Position = UDim2.new(0.5, -170, 1, -158),
	BackgroundColor3 = COLORS.bar,
	BorderSizePixel = 0,
	Active = true,
	Parent = screenGui,
})
corner(bar, 22)

local nowPlaying = create("TextLabel", {
	Name = "NowPlaying",
	Size = UDim2.new(1, -60, 0, 17),
	Position = UDim2.new(0, 20, 0, 9),
	BackgroundTransparency = 1,
	Text = "",
	TextColor3 = COLORS.white,
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = bar,
})

local nowArtist = create("TextLabel", {
	Name = "NowArtist",
	Size = UDim2.new(1, -60, 0, 14),
	Position = UDim2.new(0, 20, 0, 27),
	BackgroundTransparency = 1,
	Text = "",
	TextColor3 = COLORS.dim,
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Enum.Font.Gotham,
	TextSize = 12,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = bar,
})

-- Eye: hides the bar, leaving only the floating circle.
local eyeBtn = create("ImageButton", {
	Name = "EyeBtn",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 12),
	Size = UDim2.fromOffset(24, 24),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Parent = bar,
})
createIcon(eyeBtn, 20, COLORS.icon).set("eyeFill", "◉")

-- Floating circle: reopens the UI. Parented to the ScreenGui so it stays
-- visible while the bar is hidden. Draggable; a tap (no drag) reopens.
local floatBtn = create("ImageButton", {
	Name = "FloatToggle",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 24, 1, -24),
	Size = UDim2.fromOffset(52, 52),
	BackgroundColor3 = COLORS.accent,
	AutoButtonColor = true,
	Visible = false,
	Parent = screenGui,
})
corner(floatBtn)
createIcon(floatBtn, 32, COLORS.white).set("musicNote", "♪")

eyeBtn.MouseButton1Click:Connect(function()
	bar.Visible = false
	floatBtn.Visible = true
end)

Lib.makeDraggable(floatBtn, floatBtn, function()
	bar.Visible = true
	floatBtn.Visible = false
end)

-- The bar background drags the whole widget; buttons consume their own input.
Lib.makeDraggable(bar, bar)

-- ================= Progress bar =================

local progressTrack = create("Frame", {
	Name = "Track",
	Size = UDim2.new(1, -40, 0, 4),
	Position = UDim2.new(0, 20, 0, 48),
	BackgroundColor3 = COLORS.track,
	BorderSizePixel = 0,
	Parent = bar,
})
corner(progressTrack)

local progressFill = create("Frame", {
	Name = "Fill",
	Size = UDim2.new(0, 0, 1, 0),
	BackgroundColor3 = COLORS.white,
	BorderSizePixel = 0,
	Parent = progressTrack,
})
corner(progressFill)

local progressKnob = create("Frame", {
	Name = "Knob",
	Size = UDim2.fromOffset(11, 11),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0, 0, 0.5, 0),
	BackgroundColor3 = COLORS.white,
	BorderSizePixel = 0,
	ZIndex = 2,
	Parent = progressTrack,
})
corner(progressKnob)

-- Invisible, taller touch zone so seeking is easy on mobile.
local seekHit = create("TextButton", {
	Name = "SeekHit",
	Size = UDim2.new(1, 0, 0, 26),
	Position = UDim2.new(0, 0, 0.5, -13),
	BackgroundTransparency = 1,
	Text = "",
	Parent = progressTrack,
})

local function setProgress(rel)
	rel = math.clamp(rel, 0, 1)
	progressFill.Size = UDim2.new(rel, 0, 1, 0)
	progressKnob.Position = UDim2.new(rel, 0, 0.5, 0)
end

local function seekTo(rel)
	setProgress(rel)
	if sound.TimeLength > 0 then
		sound.TimePosition = math.clamp(rel, 0, 1) * sound.TimeLength
	end
end

local isSeeking = Lib.makeSlider(seekHit, function(pos)
	seekTo((pos.X - progressTrack.AbsolutePosition.X) / progressTrack.AbsoluteSize.X)
end)

-- Live progress while not dragging the knob.
Lib.track(RunService.RenderStepped:Connect(function()
	if not isSeeking() and sound.TimeLength > 0 then
		setProgress(sound.TimePosition / sound.TimeLength)
	end
end))

-- ================= Transport controls =================

local controls = create("Frame", {
	Name = "Controls",
	Size = UDim2.new(1, -28, 0, 46),
	Position = UDim2.new(0, 14, 1, -52),
	BackgroundTransparency = 1,
	Parent = bar,
})

local controlsLayout = create("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 16),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = controls,
})
-- Spread buttons across the full width (needs a recent Roblox build).
pcall(function()
	controlsLayout.HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween
end)

local function controlButton(order, iconName, glyph, tint)
	local btn = create("ImageButton", {
		Size = UDim2.fromOffset(38, 38),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		LayoutOrder = order,
		Parent = controls,
	})
	local icon = createIcon(btn, 23, tint or COLORS.icon)
	icon.set(iconName, glyph)
	return btn, icon
end

-- Menu button: hand-drawn hamburger (3 rounded lines).
local menuBtn = create("ImageButton", {
	Size = UDim2.fromOffset(38, 38),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	LayoutOrder = 1,
	Parent = controls,
})
for i = 0, 2 do
	local line = create("Frame", {
		Name = "Line" .. i,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(16, 2),
		Position = UDim2.new(0.5, 0, 0.5, (i - 1) * 5),
		BackgroundColor3 = COLORS.icon,
		BorderSizePixel = 0,
		Parent = menuBtn,
	})
	corner(line)
end

local prevBtn = controlButton(2, "backwardEndFill", "⏮")

-- Center play/pause: filled white circle.
local playBtn = create("ImageButton", {
	Size = UDim2.fromOffset(46, 46),
	BackgroundColor3 = COLORS.white,
	AutoButtonColor = true,
	LayoutOrder = 3,
	Parent = controls,
})
corner(playBtn)
local playIcon = createIcon(playBtn, 20, COLORS.bar, 18)

local nextBtn = controlButton(4, "forwardEndFill", "⏭")
local heartBtn, heartIcon = controlButton(5, "heart", "♡", COLORS.white)

-- ================= Volume bar =================

-- Child of `bar`, so it drags along with the player.
local volBar = create("Frame", {
	Name = "VolumeBar",
	Size = UDim2.new(0, 54, 1, 0),
	Position = UDim2.new(1, 10, 0, 0),
	BackgroundColor3 = COLORS.bar,
	BorderSizePixel = 0,
	Parent = bar,
})
corner(volBar, 22)

local volTrack = create("Frame", {
	Name = "VolTrack",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 14),
	Size = UDim2.new(0, 6, 1, -52),
	BackgroundColor3 = COLORS.track,
	BorderSizePixel = 0,
	Parent = volBar,
})
corner(volTrack)

-- Fill grows bottom-to-top.
local volFill = create("Frame", {
	Name = "VolFill",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, 0),
	Size = UDim2.new(1, 0, sound.Volume, 0),
	BackgroundColor3 = COLORS.white,
	BorderSizePixel = 0,
	Parent = volTrack,
})
corner(volFill)

local volKnob = create("Frame", {
	Name = "VolKnob",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 1 - sound.Volume, 0),
	Size = UDim2.fromOffset(12, 12),
	BackgroundColor3 = COLORS.white,
	BorderSizePixel = 0,
	ZIndex = 2,
	Parent = volTrack,
})
corner(volKnob)

local volHit = create("TextButton", {
	Name = "VolHit",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 10),
	Size = UDim2.new(0, 34, 1, -46),
	BackgroundTransparency = 1,
	Text = "",
	Parent = volBar,
})

local muteBtn = create("ImageButton", {
	Name = "MuteBtn",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -8),
	Size = UDim2.fromOffset(24, 24),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Parent = volBar,
})
local muteIcon = createIcon(muteBtn, 20, COLORS.icon, 15)

local function updateMuteIcon()
	local muted = sound.Volume <= 0.001
	local name
	if muted then
		name = "speakerSlashFill"
	elseif sound.Volume < 0.5 then
		name = "speakerWave1Fill"
	else
		name = "speakerWave2Fill"
	end
	muteIcon.set(name, muted and "×" or "♪")
	-- Muted = accent so it stands out.
	muteIcon.tint(muted and COLORS.accent or COLORS.icon)
end

local function applyVolume(rel)
	rel = math.clamp(rel, 0, 1)
	sound.Volume = rel
	volFill.Size = UDim2.new(1, 0, rel, 0)
	volKnob.Position = UDim2.new(0.5, 0, 1 - rel, 0)
	updateMuteIcon()
end

-- Vertical mapping: top = 100%, bottom = 0%.
Lib.makeSlider(volHit, function(pos)
	applyVolume(1 - (pos.Y - volTrack.AbsolutePosition.Y) / volTrack.AbsoluteSize.Y)
end)

local lastVolume = sound.Volume
muteBtn.MouseButton1Click:Connect(function()
	if sound.Volume > 0.001 then
		lastVolume = sound.Volume
		applyVolume(0)
	else
		applyVolume(lastVolume > 0.05 and lastVolume or 0.5)
	end
end)

updateMuteIcon()

-- ================= Menu panel =================

local PANEL_HEIGHT = 328
local panel = create("Frame", {
	Name = "Menu",
	Size = UDim2.new(1, 0, 0, PANEL_HEIGHT),
	Position = UDim2.new(0, 0, 0, -(PANEL_HEIGHT + 8)),
	BackgroundColor3 = COLORS.bar,
	BorderSizePixel = 0,
	Visible = false,
	Parent = bar,
})
corner(panel, 22)
padding(panel, 12, 12, 12, 12)

local function makeTab(text, xScale, xOffset)
	local tab = create("TextButton", {
		Size = UDim2.new(0.5, -3, 0, 32),
		Position = UDim2.new(xScale, xOffset, 0, 0),
		BackgroundColor3 = COLORS.field,
		AutoButtonColor = false,
		Text = text,
		TextColor3 = COLORS.white,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		Parent = panel,
	})
	corner(tab, 8)
	return tab
end

local tabAll = makeTab("Todas", 0, 0)
local tabFav = makeTab("Favoritas", 0.5, 3)

local searchBox = create("TextBox", {
	Name = "Search",
	Position = UDim2.new(0, 0, 0, 42),
	Size = UDim2.new(1, 0, 0, 32),
	BackgroundColor3 = COLORS.field,
	TextColor3 = COLORS.white,
	PlaceholderText = "Buscar por nombre, artista o género",
	PlaceholderColor3 = COLORS.dim,
	ClearTextOnFocus = false,
	Font = Enum.Font.Gotham,
	TextSize = 13,
	Text = "",
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = panel,
})
corner(searchBox, 8)
padding(searchBox, 0, 0, 10, 10)

local genreScroll = create("ScrollingFrame", {
	Name = "Genres",
	Position = UDim2.new(0, 0, 0, 82),
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 0,
	ScrollingDirection = Enum.ScrollingDirection.X,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.X,
	Parent = panel,
})
create("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 6),
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = genreScroll,
})

local listScroll = create("ScrollingFrame", {
	Name = "List",
	Position = UDim2.new(0, 0, 0, 120),
	Size = UDim2.new(1, 0, 1, -120),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = COLORS.dim,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = panel,
})
create("UIListLayout", {
	Padding = UDim.new(0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = listScroll,
})

menuBtn.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible
end)

-- ================= Player state =================

local currentIndex = 1
local currentTrackId = ""

local rebuildLists, highlightCurrent -- forward declarations

local function refreshHeart()
	local fav = isFavorite(currentTrackId)
	heartIcon.set(fav and "heartFill" or "heart", fav and "♥" or "♡")
	heartIcon.tint(fav and COLORS.accent or COLORS.white)
end

local function updateNowPlaying()
	local t = trackById[currentTrackId]
	nowPlaying.Text = t and t.name or currentTrackId
	nowArtist.Text = t and trackSubtitle(t) or ""
end

local function setPlayGlyph()
	local playing = sound.IsPlaying
	playIcon.set(playing and "pauseFill" or "playFill", playing and "❚❚" or "▶")
end

-- Updates every piece of UI bound to the current track (without playing it).
local function setCurrent(id)
	currentTrackId = id
	updateNowPlaying()
	refreshHeart()
	highlightCurrent()
end

local function loadAndPlay()
	local assetId = currentTrackId:gsub("%D", "")
	if assetId == "" then
		return
	end
	sound:Stop()
	sound.SoundId = "rbxassetid://" .. assetId
	local ok, err = pcall(sound.Play, sound)
	if not ok then
		warn("[music] failed to play " .. assetId .. ": " .. tostring(err))
	end
	setPlayGlyph()
end

-- If the ID belongs to the main list, currentIndex syncs so prev/next
-- continue from there.
local function playId(id)
	local index = trackIndexById[id]
	if index then
		currentIndex = index
	end
	setCurrent(id)
	loadAndPlay()
end

local function playStep(offset)
	currentIndex = (currentIndex + offset - 1) % #musicTracks + 1
	setCurrent(musicTracks[currentIndex].id)
	loadAndPlay()
end

local function togglePlay()
	if sound.IsPlaying then
		sound:Pause()
	elseif sound.SoundId ~= "" and sound.TimePosition > 0 then
		sound:Resume()
	else
		loadAndPlay()
	end
	setPlayGlyph()
end

prevBtn.MouseButton1Click:Connect(function()
	playStep(-1)
end)
nextBtn.MouseButton1Click:Connect(function()
	playStep(1)
end)
playBtn.MouseButton1Click:Connect(togglePlay)

-- Auto-advance when the song ends (never repeats it).
sound.Ended:Connect(function()
	playStep(1)
end)

-- Heart toggles the current track as favorite. State is per-song.
heartBtn.MouseButton1Click:Connect(function()
	if currentTrackId == "" then
		return
	end
	toggleFavorite(currentTrackId)
	refreshHeart()
	rebuildLists()
end)

-- ================= Track list (tabs + search + genre filter) =================

local currentTab = "all" -- "all" | "fav"
local searchQuery = ""
local selectedGenre = "" -- "" = all genres

-- Rows indexed by id, so the playing row can be highlighted in place.
local rowsById = {}

local function passesFilters(id)
	local t = trackById[id]
	if selectedGenre ~= "" and (not t or t.genre ~= selectedGenre) then
		return false
	end
	if searchQuery ~= "" then
		local hay = searchText[id] or id:lower()
		if not hay:find(searchQuery, 1, true) then
			return false
		end
	end
	return true
end

local function makeRow(id, order)
	local t = trackById[id]

	local rowBtn = create("TextButton", {
		-- -10 keeps the scroll bar from covering the ♥ marker.
		Size = UDim2.new(1, -10, 0, 40),
		BackgroundColor3 = COLORS.field,
		AutoButtonColor = true,
		Text = "",
		LayoutOrder = order,
		Parent = listScroll,
	})
	corner(rowBtn, 6)

	create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -44, 0, 18),
		Position = UDim2.new(0, 10, 0, 4),
		BackgroundTransparency = 1,
		Text = t and t.name or id,
		TextColor3 = COLORS.white,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = rowBtn,
	})

	local subLabel = create("TextLabel", {
		Name = "Subtitle",
		Size = UDim2.new(1, -44, 0, 14),
		Position = UDim2.new(0, 10, 0, 21),
		BackgroundTransparency = 1,
		Text = t and trackSubtitle(t) or ("ID " .. id),
		TextColor3 = COLORS.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.Gotham,
		TextSize = 11,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = rowBtn,
	})

	local mark = create("TextLabel", {
		Name = "FavMark",
		Size = UDim2.fromOffset(24, 40),
		Position = UDim2.new(1, -30, 0, 0),
		BackgroundTransparency = 1,
		Text = isFavorite(id) and "♥" or "",
		TextColor3 = COLORS.accent,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		Parent = rowBtn,
	})

	rowsById[id] = { button = rowBtn, sub = subLabel, mark = mark }

	rowBtn.MouseButton1Click:Connect(function()
		playId(id)
	end)
end

local function makeEmptyMessage(text)
	create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = COLORS.dim,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		LayoutOrder = 1,
		Parent = listScroll,
	})
end

rebuildLists = function()
	table.clear(rowsById)
	for _, child in ipairs(listScroll:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	if currentTab == "fav" and #favorites == 0 then
		makeEmptyMessage("Todavía no marcaste favoritos.\nTocá el corazón para agregar.")
		return
	end

	local count = 0
	if currentTab == "fav" then
		for _, id in ipairs(favorites) do
			if passesFilters(id) then
				count += 1
				makeRow(id, count)
			end
		end
	else
		for _, t in ipairs(musicTracks) do
			if passesFilters(t.id) then
				count += 1
				makeRow(t.id, count)
			end
		end
	end

	if count == 0 and (searchQuery ~= "" or selectedGenre ~= "") then
		makeEmptyMessage("Sin resultados con ese filtro.")
	end

	highlightCurrent()
end

highlightCurrent = function()
	for id, r in pairs(rowsById) do
		local sel = id == currentTrackId
		r.button.BackgroundColor3 = sel and COLORS.accent or COLORS.field
		r.sub.TextColor3 = sel and COLORS.white or COLORS.dim
		if r.mark.Text ~= "" then
			r.mark.TextColor3 = sel and COLORS.white or COLORS.accent
		end
	end
end

local function styleTabs()
	tabAll.BackgroundColor3 = (currentTab == "all") and COLORS.field or COLORS.panel
	tabAll.TextColor3 = (currentTab == "all") and COLORS.white or COLORS.dim
	tabFav.BackgroundColor3 = (currentTab == "fav") and COLORS.field or COLORS.panel
	tabFav.TextColor3 = (currentTab == "fav") and COLORS.white or COLORS.dim
end

local function setTab(tab)
	currentTab = tab
	styleTabs()
	rebuildLists()
end

tabAll.MouseButton1Click:Connect(function()
	setTab("all")
end)
tabFav.MouseButton1Click:Connect(function()
	setTab("fav")
end)

-- Live search while typing.
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	searchQuery = searchBox.Text:lower()
	rebuildLists()
end)

-- Genre chips (radio select): "Todos" ("" = no filter) + one per genre.
local genreChips = {}

local function styleGenreChips()
	for _, chip in ipairs(genreChips) do
		local active = chip.value == selectedGenre
		chip.button.BackgroundColor3 = active and COLORS.accent or COLORS.field
		chip.button.TextColor3 = active and COLORS.white or COLORS.dim
	end
end

local function makeGenreChip(label, value, order)
	local chip = create("TextButton", {
		Name = "Chip",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = COLORS.field,
		AutoButtonColor = false,
		Text = label,
		TextColor3 = COLORS.dim,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		LayoutOrder = order,
		Parent = genreScroll,
	})
	corner(chip, 8)
	padding(chip, 0, 0, 12, 12)

	chip.MouseButton1Click:Connect(function()
		selectedGenre = value
		styleGenreChips()
		rebuildLists()
	end)

	table.insert(genreChips, { value = value, button = chip })
end

makeGenreChip("Todos", "", 1)
for i, g in ipairs(genres) do
	makeGenreChip(g, g, i + 1)
end
styleGenreChips()

-- ================= Init =================

loadFavorites()
setTab("all")
setCurrent(musicTracks[currentIndex].id)
setPlayGlyph()

-- Cleanup hook for the next run: kills Lib's service connections, the sound
-- and the UI.
_G.MusicTesterCleanup = function()
	pcall(Lib.cleanup)
	pcall(function()
		sound:Destroy()
	end)
	pcall(function()
		screenGui:Destroy()
	end)
end
