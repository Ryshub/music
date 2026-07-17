local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Re-run: if an instance is already running, clean it up (UI + sound +
-- connections) to replace it instead of creating a duplicate UI.
if _G.MusicTesterCleanup then
	pcall(_G.MusicTesterCleanup)
	_G.MusicTesterCleanup = nil
end

-- Service connections (RunService/UserInputService) that live outside the
-- UI: stored here so they can be disconnected on re-run.
local uiConnections = {}
local function trackConn(conn)
	table.insert(uiConnections, conn)
	return conn
end

-- Tracks: live in tracks.lua (separate component). main.lua downloads it
-- from the repo over HTTP and loads it. On failure, uses a minimal fallback
-- so the UI still starts.
local TRACKS_URL = "https://raw.githubusercontent.com/Ryshub/music/main/tracks.lua"

local function loadTracks()
	local ok, result = pcall(function()
		local src
		for _, getter in ipairs({ game.HttpGetAsync, game.HttpGet }) do
			local good, res = pcall(getter, game, TRACKS_URL)
			if good and type(res) == "string" and res ~= "" then
				src = res
				break
			end
		end
		if not src then
			local good, res = pcall(function()
				return HttpService:GetAsync(TRACKS_URL)
			end)
			if good then
				src = res
			end
		end
		return src and loadstring(src)() or nil
	end)
	if ok and type(result) == "table" and #result > 0 then
		return result
	end
	return nil
end

local musicTracks = loadTracks()
	or {
		{ genre = "Funk", name = "67 KID FUNK", artist = "DRIFTGØD", id = "84142247103485" },
	}

local genres = {}
do
	local seen = {}
	for _, t in ipairs(musicTracks) do
		if t.genre and not seen[t.genre] then
			seen[t.genre] = true
			table.insert(genres, t.genre)
		end
	end
end

local currentIndex = 1
local currentTrackId = ""

-- Favorites persisted to the executor's "ryshub/music" folder (writefile/readfile).
local favorites = {}
local SAVE_DIR = "ryshub/music"
local FAV_FILE = SAVE_DIR .. "/favorites.json"

-- Creates ryshub/ and ryshub/music/ if missing (in case makefolder doesn't nest).
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

-- Icon loader: downloads Footagesus' icon module over HTTP and caches it.
-- Uses the "sfsymbols" pack (filled variants); falls back to a text glyph.
local LUCIDE_URL = "https://raw.githubusercontent.com/Footagesus/Icons/main/Main-v2.lua"
local ICON_PACK = "sfsymbols"
local LucideModule = nil

local function getLucide()
	if LucideModule then
		return LucideModule
	end
	if type(_G) == "table" and _G.Lucide then
		LucideModule = _G.Lucide
		return LucideModule
	end
	local ok, mod = pcall(function()
		local src
		local getters = { game.HttpGetAsync, game.HttpGet }
		for _, getter in ipairs(getters) do
			local good, res = pcall(getter, game, LUCIDE_URL)
			if good and type(res) == "string" and res ~= "" then
				src = res
				break
			end
		end
		if not src then
			local good, res = pcall(function()
				return HttpService:GetAsync(LUCIDE_URL)
			end)
			if good then
				src = res
			end
		end
		return src and loadstring(src)() or nil
	end)
	if ok and mod then
		LucideModule = mod
		_G.Lucide = LucideModule
	end
	return LucideModule
end

-- Returns { Image, ImageRectOffset, ImageRectSize } or nil
-- Always requests the explicit pack (ICON_PACK) so it doesn't depend on
-- the default type another script might have left.
local function readIconAsset(name)
	local lucide = getLucide()
	if not lucide or not name then
		return nil
	end

	local data
	for _, fnName in ipairs({ "Icon2", "Icon" }) do
		if type(lucide[fnName]) == "function" then
			local ok, res = pcall(lucide[fnName], name, ICON_PACK, true)
			if ok and res then
				data = res
				break
			end
		end
	end

	if type(data) == "string" then
		return { Image = data, ImageRectOffset = Vector2.zero, ImageRectSize = Vector2.zero }
	elseif type(data) == "table" and data[1] and data[2] then
		local image = data[1]
		if type(image) == "number" then
			image = "rbxassetid://" .. tostring(image)
		end
		return {
			Image = image,
			ImageRectOffset = data[2].ImageRectPosition or data[2].ImageRectOffset or Vector2.zero,
			ImageRectSize = data[2].ImageRectSize or Vector2.zero,
		}
	end

	local set = lucide.Icons and lucide.Icons[ICON_PACK]
	local entry = set and set.Icons and set.Icons[name]
	if entry then
		local image = (set.Spritesheets and set.Spritesheets[tostring(entry.Image)]) or entry.Image
		if type(image) == "number" then
			image = "rbxassetid://" .. tostring(image)
		end
		return {
			Image = image,
			ImageRectOffset = entry.ImageRectPosition or entry.ImageRectOffset or Vector2.zero,
			ImageRectSize = entry.ImageRectSize or Vector2.zero,
		}
	end

	return nil
end

local function applyIcon(imageObject, name)
	local asset = readIconAsset(name)
	if not asset or type(asset.Image) ~= "string" or asset.Image == "" then
		imageObject.Image = ""
		return false
	end
	imageObject.Image = asset.Image
	if typeof(asset.ImageRectOffset) == "Vector2" then
		imageObject.ImageRectOffset = asset.ImageRectOffset
	end
	if typeof(asset.ImageRectSize) == "Vector2" then
		imageObject.ImageRectSize = asset.ImageRectSize
	end
	return true
end

local function setButtonIcon(btn, iconName, fallbackGlyph, iconSize, color)
	local img = Instance.new("ImageLabel")
	img.Name = "Icon"
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Position = UDim2.new(0.5, 0, 0.5, 0)
	img.Size = UDim2.fromOffset(iconSize, iconSize)
	img.BackgroundTransparency = 1
	img.Image = ""
	img.ImageColor3 = color
	img.Parent = btn

	local fb = Instance.new("TextLabel")
	fb.Name = "Fallback"
	fb.Size = UDim2.new(1, 0, 1, 0)
	fb.BackgroundTransparency = 1
	fb.Text = fallbackGlyph
	fb.TextColor3 = color
	fb.Font = Enum.Font.GothamBold
	fb.TextSize = math.floor(iconSize * 0.9)
	fb.Parent = btn

	if applyIcon(img, iconName) then
		fb.Visible = false
	else
		img.Visible = false
		fb.Visible = true
	end
	return img, fb
end

local sound = Instance.new("Sound")
sound.Name = "MusicTester"
sound.Volume = 0.5
sound.Looped = false
sound.Parent = SoundService

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MusicTesterGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- ================= Main bar =================
local bar = Instance.new("Frame")
bar.Name = "PlayerBar"
bar.Size = UDim2.fromOffset(340, 112)
bar.Position = UDim2.new(0.5, -170, 1, -158)
bar.BackgroundColor3 = COLORS.bar
bar.BorderSizePixel = 0
bar.Active = true
bar.Parent = screenGui

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0, 22)
barCorner.Parent = bar

local nowPlaying = Instance.new("TextLabel")
nowPlaying.Name = "NowPlaying"
nowPlaying.Size = UDim2.new(1, -60, 0, 17)
nowPlaying.Position = UDim2.new(0, 20, 0, 9)
nowPlaying.BackgroundTransparency = 1
nowPlaying.Text = ""
nowPlaying.TextColor3 = COLORS.white
nowPlaying.TextXAlignment = Enum.TextXAlignment.Left
nowPlaying.Font = Enum.Font.GothamBold
nowPlaying.TextSize = 14
nowPlaying.TextTruncate = Enum.TextTruncate.AtEnd
nowPlaying.Parent = bar

local nowArtist = Instance.new("TextLabel")
nowArtist.Name = "NowArtist"
nowArtist.Size = UDim2.new(1, -60, 0, 14)
nowArtist.Position = UDim2.new(0, 20, 0, 27)
nowArtist.BackgroundTransparency = 1
nowArtist.Text = ""
nowArtist.TextColor3 = COLORS.dim
nowArtist.TextXAlignment = Enum.TextXAlignment.Left
nowArtist.Font = Enum.Font.Gotham
nowArtist.TextSize = 12
nowArtist.TextTruncate = Enum.TextTruncate.AtEnd
nowArtist.Parent = bar

local eyeBtn = Instance.new("ImageButton")
eyeBtn.Name = "EyeBtn"
eyeBtn.AnchorPoint = Vector2.new(1, 0)
eyeBtn.Position = UDim2.new(1, -14, 0, 12)
eyeBtn.Size = UDim2.fromOffset(24, 24)
eyeBtn.BackgroundTransparency = 1
eyeBtn.Image = ""
eyeBtn.AutoButtonColor = false
eyeBtn.Parent = bar
setButtonIcon(eyeBtn, "eyeFill", "◉", 20, COLORS.icon)

-- Floating circle (bottom-right): reopens the UI. Placed in the ScreenGui
-- so it stays visible when the bar is hidden.
local floatBtn = Instance.new("ImageButton")
floatBtn.Name = "FloatToggle"
floatBtn.AnchorPoint = Vector2.new(0, 1)
floatBtn.Position = UDim2.new(0, 24, 1, -24)
floatBtn.Size = UDim2.fromOffset(52, 52)
floatBtn.BackgroundColor3 = COLORS.accent
floatBtn.Image = ""
floatBtn.AutoButtonColor = true
floatBtn.Visible = false
floatBtn.Parent = screenGui

local floatCorner = Instance.new("UICorner")
floatCorner.CornerRadius = UDim.new(1, 0)
floatCorner.Parent = floatBtn

setButtonIcon(floatBtn, "musicNote", "♪", 24, COLORS.white)

eyeBtn.MouseButton1Click:Connect(function()
	bar.Visible = false
	floatBtn.Visible = true
end)

-- The floating button is draggable. A tap (no drag) reopens the UI;
-- if dragged, it just moved position.
local floatDragging = false
local floatMoved = false
local floatStart, floatStartPos

floatBtn.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		floatDragging = true
		floatMoved = false
		floatStart = input.Position
		floatStartPos = floatBtn.Position
	end
end)

trackConn(UserInputService.InputChanged:Connect(function(input)
	if floatDragging and (input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - floatStart
		if delta.Magnitude > 6 then
			floatMoved = true
		end
		floatBtn.Position = UDim2.new(
			floatStartPos.X.Scale, floatStartPos.X.Offset + delta.X,
			floatStartPos.Y.Scale, floatStartPos.Y.Offset + delta.Y
		)
	end
end))

trackConn(UserInputService.InputEnded:Connect(function(input)
	if floatDragging and (input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch) then
		floatDragging = false
		if not floatMoved then
			bar.Visible = true
			floatBtn.Visible = false
		end
	end
end))

local track = Instance.new("Frame")
track.Name = "Track"
track.Size = UDim2.new(1, -40, 0, 4)
track.Position = UDim2.new(0, 20, 0, 48)
track.BackgroundColor3 = COLORS.track
track.BorderSizePixel = 0
track.Parent = bar

local trackCorner = Instance.new("UICorner")
trackCorner.CornerRadius = UDim.new(1, 0)
trackCorner.Parent = track

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.new(0, 0, 1, 0)
fill.BackgroundColor3 = COLORS.white
fill.BorderSizePixel = 0
fill.Parent = track

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = fill

local knob = Instance.new("Frame")
knob.Name = "Knob"
knob.Size = UDim2.fromOffset(11, 11)
knob.AnchorPoint = Vector2.new(0.5, 0.5)
knob.Position = UDim2.new(0, 0, 0.5, 0)
knob.BackgroundColor3 = COLORS.white
knob.BorderSizePixel = 0
knob.ZIndex = 2
knob.Parent = track

local knobCorner = Instance.new("UICorner")
knobCorner.CornerRadius = UDim.new(1, 0)
knobCorner.Parent = knob

local seekHit = Instance.new("TextButton")
seekHit.Name = "SeekHit"
seekHit.Size = UDim2.new(1, 0, 0, 26)
seekHit.Position = UDim2.new(0, 0, 0.5, -13)
seekHit.BackgroundTransparency = 1
seekHit.Text = ""
seekHit.Parent = track

local row = Instance.new("Frame")
row.Name = "Controls"
row.Size = UDim2.new(1, -28, 0, 46)
row.Position = UDim2.new(0, 14, 1, -52)
row.BackgroundTransparency = 1
row.Parent = bar

local rowLayout = Instance.new("UIListLayout")
rowLayout.FillDirection = Enum.FillDirection.Horizontal
rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
rowLayout.Padding = UDim.new(0, 16)
rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowLayout.Parent = row
pcall(function()
	rowLayout.HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween
end)

local function makeIconButton(iconName, fallbackGlyph, boxSize, iconSize, order, tint)
	local btn = Instance.new("ImageButton")
	btn.Size = UDim2.fromOffset(boxSize, boxSize)
	btn.BackgroundTransparency = 1
	btn.Image = ""
	btn.AutoButtonColor = false
	btn.LayoutOrder = order
	btn.Parent = row

	local img = Instance.new("ImageLabel")
	img.Name = "Icon"
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Position = UDim2.new(0.5, 0, 0.5, 0)
	img.Size = UDim2.fromOffset(iconSize, iconSize)
	img.BackgroundTransparency = 1
	img.Image = ""
	img.ImageColor3 = tint or COLORS.icon
	img.Parent = btn

	local fb = Instance.new("TextLabel")
	fb.Name = "Fallback"
	fb.Size = UDim2.new(1, 0, 1, 0)
	fb.BackgroundTransparency = 1
	fb.Text = fallbackGlyph
	fb.TextColor3 = tint or COLORS.icon
	fb.Font = Enum.Font.GothamBold
	fb.TextSize = math.floor(iconSize * 0.9)
	fb.Visible = false
	fb.Parent = btn

	if applyIcon(img, iconName) then
		fb.Visible = false
		img.Visible = true
	else
		img.Visible = false
		fb.Visible = true
	end

	return btn, img, fb
end

local menuBtn = Instance.new("ImageButton")
menuBtn.Size = UDim2.fromOffset(38, 38)
menuBtn.BackgroundTransparency = 1
menuBtn.Image = ""
menuBtn.AutoButtonColor = false
menuBtn.LayoutOrder = 1
menuBtn.Parent = row

do
	local lineWidth = 16
	local lineHeight = 2
	local gap = 5
	for i = 0, 2 do
		local line = Instance.new("Frame")
		line.Name = "Line" .. i
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.Size = UDim2.fromOffset(lineWidth, lineHeight)
		line.Position = UDim2.new(0.5, 0, 0.5, (i - 1) * gap)
		line.BackgroundColor3 = COLORS.icon
		line.BorderSizePixel = 0
		line.Parent = menuBtn

		local lineCorner = Instance.new("UICorner")
		lineCorner.CornerRadius = UDim.new(1, 0)
		lineCorner.Parent = line
	end
end

local prevBtn = makeIconButton("backwardEndFill", "⏮", 38, 23, 2)

local playBtn = Instance.new("ImageButton")
playBtn.Size = UDim2.fromOffset(46, 46)
playBtn.BackgroundColor3 = COLORS.white
playBtn.Image = ""
playBtn.AutoButtonColor = true
playBtn.LayoutOrder = 3
playBtn.Parent = row

local playCorner = Instance.new("UICorner")
playCorner.CornerRadius = UDim.new(1, 0)
playCorner.Parent = playBtn

local playIcon = Instance.new("ImageLabel")
playIcon.Name = "Icon"
playIcon.AnchorPoint = Vector2.new(0.5, 0.5)
playIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
playIcon.Size = UDim2.fromOffset(20, 20)
playIcon.BackgroundTransparency = 1
playIcon.Image = ""
playIcon.ImageColor3 = COLORS.bar
playIcon.Parent = playBtn

local playFallback = Instance.new("TextLabel")
playFallback.Name = "Fallback"
playFallback.Size = UDim2.new(1, 0, 1, 0)
playFallback.BackgroundTransparency = 1
playFallback.Text = "▶"
playFallback.TextColor3 = COLORS.bar
playFallback.Font = Enum.Font.GothamBold
playFallback.TextSize = 18
playFallback.Visible = false
playFallback.Parent = playBtn

local nextBtn = makeIconButton("forwardEndFill", "⏭", 38, 23, 4)
local heartBtn, heartIcon, heartFallback = makeIconButton("heart", "♡", 38, 23, 5, COLORS.white)

-- ================= Panel / menu (toggled by the 3 lines) =================
local PANEL_HEIGHT = 328
local panel = Instance.new("Frame")
panel.Name = "Menu"
panel.Size = UDim2.new(1, 0, 0, PANEL_HEIGHT)
panel.Position = UDim2.new(0, 0, 0, -(PANEL_HEIGHT + 8))
panel.BackgroundColor3 = COLORS.bar
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = bar

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 22)
panelCorner.Parent = panel

local panelPad = Instance.new("UIPadding")
panelPad.PaddingTop = UDim.new(0, 12)
panelPad.PaddingBottom = UDim.new(0, 12)
panelPad.PaddingLeft = UDim.new(0, 12)
panelPad.PaddingRight = UDim.new(0, 12)
panelPad.Parent = panel

local function makeTab(text, xScale, xOffset)
	local tab = Instance.new("TextButton")
	tab.Size = UDim2.new(0.5, -3, 0, 32)
	tab.Position = UDim2.new(xScale, xOffset, 0, 0)
	tab.BackgroundColor3 = COLORS.field
	tab.AutoButtonColor = false
	tab.Text = text
	tab.TextColor3 = COLORS.white
	tab.Font = Enum.Font.GothamBold
	tab.TextSize = 13
	tab.Parent = panel

	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(0, 8)
	tc.Parent = tab
	return tab
end

local tabAll = makeTab("Todas", 0, 0)
local tabFav = makeTab("Favoritas", 0.5, 3)

local searchBox = Instance.new("TextBox")
searchBox.Name = "Search"
searchBox.Position = UDim2.new(0, 0, 0, 42)
searchBox.Size = UDim2.new(1, 0, 0, 32)
searchBox.BackgroundColor3 = COLORS.field
searchBox.TextColor3 = COLORS.white
searchBox.PlaceholderText = "Buscar por nombre, artista o género"
searchBox.PlaceholderColor3 = COLORS.dim
searchBox.ClearTextOnFocus = false
searchBox.Font = Enum.Font.Gotham
searchBox.TextSize = 13
searchBox.Text = ""
searchBox.TextXAlignment = Enum.TextXAlignment.Left
searchBox.Parent = panel

local searchCorner = Instance.new("UICorner")
searchCorner.CornerRadius = UDim.new(0, 8)
searchCorner.Parent = searchBox

local searchPad = Instance.new("UIPadding")
searchPad.PaddingLeft = UDim.new(0, 10)
searchPad.PaddingRight = UDim.new(0, 10)
searchPad.Parent = searchBox

local genreScroll = Instance.new("ScrollingFrame")
genreScroll.Name = "Genres"
genreScroll.Position = UDim2.new(0, 0, 0, 82)
genreScroll.Size = UDim2.new(1, 0, 0, 30)
genreScroll.BackgroundTransparency = 1
genreScroll.BorderSizePixel = 0
genreScroll.ScrollBarThickness = 0
genreScroll.ScrollingDirection = Enum.ScrollingDirection.X
genreScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
genreScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
genreScroll.Parent = panel

local genreLayout = Instance.new("UIListLayout")
genreLayout.FillDirection = Enum.FillDirection.Horizontal
genreLayout.Padding = UDim.new(0, 6)
genreLayout.VerticalAlignment = Enum.VerticalAlignment.Center
genreLayout.SortOrder = Enum.SortOrder.LayoutOrder
genreLayout.Parent = genreScroll

local listScroll = Instance.new("ScrollingFrame")
listScroll.Name = "List"
listScroll.Position = UDim2.new(0, 0, 0, 120)
listScroll.Size = UDim2.new(1, 0, 1, -120)
listScroll.BackgroundTransparency = 1
listScroll.BorderSizePixel = 0
listScroll.ScrollBarThickness = 4
listScroll.ScrollBarImageColor3 = COLORS.dim
listScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
listScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
listScroll.Parent = panel

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 4)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = listScroll

-- ================= Volume bar (vertical, on the right) =================
-- Same look as the playback bar. It's a child of `bar`, so it drags
-- along with it.
local VOL_WIDTH = 54
local volBar = Instance.new("Frame")
volBar.Name = "VolumeBar"
volBar.Size = UDim2.new(0, VOL_WIDTH, 1, 0)
volBar.Position = UDim2.new(1, 10, 0, 0)
volBar.BackgroundColor3 = COLORS.bar
volBar.BorderSizePixel = 0
volBar.Parent = bar

local volBarCorner = Instance.new("UICorner")
volBarCorner.CornerRadius = UDim.new(0, 22)
volBarCorner.Parent = volBar

local volTrack = Instance.new("Frame")
volTrack.Name = "VolTrack"
volTrack.AnchorPoint = Vector2.new(0.5, 0)
volTrack.Position = UDim2.new(0.5, 0, 0, 14)
volTrack.Size = UDim2.new(0, 6, 1, -52)
volTrack.BackgroundColor3 = COLORS.track
volTrack.BorderSizePixel = 0
volTrack.Parent = volBar

local volTrackCorner = Instance.new("UICorner")
volTrackCorner.CornerRadius = UDim.new(1, 0)
volTrackCorner.Parent = volTrack

-- The fill grows from bottom to top
local volFill = Instance.new("Frame")
volFill.Name = "VolFill"
volFill.AnchorPoint = Vector2.new(0.5, 1)
volFill.Position = UDim2.new(0.5, 0, 1, 0)
volFill.Size = UDim2.new(1, 0, sound.Volume, 0)
volFill.BackgroundColor3 = COLORS.white
volFill.BorderSizePixel = 0
volFill.Parent = volTrack

local volFillCorner = Instance.new("UICorner")
volFillCorner.CornerRadius = UDim.new(1, 0)
volFillCorner.Parent = volFill

local volKnob = Instance.new("Frame")
volKnob.Name = "VolKnob"
volKnob.AnchorPoint = Vector2.new(0.5, 0.5)
volKnob.Position = UDim2.new(0.5, 0, 1 - sound.Volume, 0)
volKnob.Size = UDim2.fromOffset(12, 12)
volKnob.BackgroundColor3 = COLORS.white
volKnob.BorderSizePixel = 0
volKnob.ZIndex = 2
volKnob.Parent = volTrack

local volKnobCorner = Instance.new("UICorner")
volKnobCorner.CornerRadius = UDim.new(1, 0)
volKnobCorner.Parent = volKnob

local volHit = Instance.new("TextButton")
volHit.Name = "VolHit"
volHit.AnchorPoint = Vector2.new(0.5, 0)
volHit.Position = UDim2.new(0.5, 0, 0, 10)
volHit.Size = UDim2.new(0, 34, 1, -46)
volHit.BackgroundTransparency = 1
volHit.Text = ""
volHit.Parent = volBar

local muteBtn = Instance.new("ImageButton")
muteBtn.Name = "MuteBtn"
muteBtn.AnchorPoint = Vector2.new(0.5, 1)
muteBtn.Position = UDim2.new(0.5, 0, 1, -8)
muteBtn.Size = UDim2.fromOffset(24, 24)
muteBtn.BackgroundTransparency = 1
muteBtn.Image = ""
muteBtn.AutoButtonColor = false
muteBtn.Parent = volBar

local muteIcon = Instance.new("ImageLabel")
muteIcon.Name = "Icon"
muteIcon.AnchorPoint = Vector2.new(0.5, 0.5)
muteIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
muteIcon.Size = UDim2.fromOffset(20, 20)
muteIcon.BackgroundTransparency = 1
muteIcon.Image = ""
muteIcon.ImageColor3 = COLORS.icon
muteIcon.Parent = muteBtn

local muteFallback = Instance.new("TextLabel")
muteFallback.Name = "Fallback"
muteFallback.Size = UDim2.new(1, 0, 1, 0)
muteFallback.BackgroundTransparency = 1
muteFallback.Text = "♪"
muteFallback.TextColor3 = COLORS.icon
muteFallback.Font = Enum.Font.GothamBold
muteFallback.TextSize = 15
muteFallback.Visible = false
muteFallback.Parent = muteBtn

local function updateMuteIcon()
	local name
	if sound.Volume <= 0.001 then
		name = "speakerSlashFill"
	elseif sound.Volume < 0.5 then
		name = "speakerWave1Fill"
	else
		name = "speakerWave2Fill"
	end
	local col = (sound.Volume <= 0.001) and COLORS.accent or COLORS.icon
	muteIcon.ImageColor3 = col
	muteFallback.TextColor3 = col
	if applyIcon(muteIcon, name) then
		muteIcon.Visible = true
		muteFallback.Visible = false
	else
		muteIcon.Visible = false
		muteFallback.Visible = true
		muteFallback.Text = (sound.Volume <= 0.001) and "×" or "♪"
	end
end

local function applyVolume(rel)
	rel = math.clamp(rel, 0, 1)
	sound.Volume = rel
	volFill.Size = UDim2.new(1, 0, rel, 0)
	volKnob.Position = UDim2.new(0.5, 0, 1 - rel, 0)
	updateMuteIcon()
end

-- Vertical: top = 100%, bottom = 0%.
local function setVolumeFromY(py)
	local rel = 1 - (py - volTrack.AbsolutePosition.Y) / volTrack.AbsoluteSize.Y
	applyVolume(rel)
end

local volDragging = false

volHit.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		volDragging = true
		setVolumeFromY(input.Position.Y)
	end
end)

trackConn(UserInputService.InputChanged:Connect(function(input)
	if volDragging and (input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch) then
		setVolumeFromY(input.Position.Y)
	end
end))

trackConn(UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		volDragging = false
	end
end))

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

-- ================= Logic =================
local function updateStatus(_)
	-- no status text in the UI; kept for compatibility
end

local function currentId()
	return (currentTrackId:gsub("%D", ""))
end

local function isFavorite(id)
	for _, v in ipairs(favorites) do
		if v == id then
			return true
		end
	end
	return false
end

local function saveFavorites()
	if writefile then
		ensureSaveFolder()
		pcall(writefile, FAV_FILE, HttpService:JSONEncode(favorites))
	end
end

local function loadFavorites()
	if readfile and isfile and isfile(FAV_FILE) then
		local ok, data = pcall(function()
			return HttpService:JSONDecode(readfile(FAV_FILE))
		end)
		if ok and type(data) == "table" then
			favorites = data
		end
	end
end

local function addFavorite(id)
	if id ~= "" and not isFavorite(id) then
		table.insert(favorites, id)
		saveFavorites()
	end
end

local function removeFavorite(id)
	for i, v in ipairs(favorites) do
		if v == id then
			table.remove(favorites, i)
			saveFavorites()
			return
		end
	end
end

local function setHeartVisual(fav)
	local col = fav and COLORS.accent or COLORS.white
	applyIcon(heartIcon, fav and "heartFill" or "heart")
	heartIcon.ImageColor3 = col
	heartFallback.Text = fav and "♥" or "♡"
	heartFallback.TextColor3 = col
end

local function refreshHeart()
	setHeartVisual(isFavorite(currentId()))
end

local function trackSubtitle(t)
	if t.artist and t.artist ~= "" then
		return t.artist
	end
	return t.genre or ""
end

local function updateNowPlaying()
	local id = currentId()
	for _, t in ipairs(musicTracks) do
		if t.id == id then
			nowPlaying.Text = t.name
			nowArtist.Text = trackSubtitle(t)
			return
		end
	end
	nowPlaying.Text = id
	nowArtist.Text = ""
end

-- Forward declaration: rebuilt whenever favorites change.
local rebuildLists, highlightCurrent

local function setPlayGlyph()
	local iconName = sound.IsPlaying and "pauseFill" or "playFill"
	if not applyIcon(playIcon, iconName) then
		playIcon.Visible = false
		playFallback.Visible = true
		playFallback.Text = sound.IsPlaying and "❚❚" or "▶"
	else
		playIcon.Visible = true
		playFallback.Visible = false
	end
end

local function setCurrentId()
	currentTrackId = musicTracks[currentIndex].id
	updateStatus()
	updateNowPlaying()
end

local function loadAndPlay()
	local musicId = currentTrackId:gsub("%D", "")

	if musicId == "" then
		updateStatus("Ingresá un ID válido")
		return
	end

	sound:Stop()
	sound.SoundId = "rbxassetid://" .. musicId
	updateStatus("Cargando: " .. musicId)

	local success, errorMessage = pcall(function()
		sound:Play()
	end)

	if success then
		updateStatus("Reproduciendo: " .. musicId)
	else
		updateStatus("Error al reproducir")
		warn(errorMessage)
	end
	setPlayGlyph()
	refreshHeart()
	updateNowPlaying()
	highlightCurrent()
end

local function togglePlay()
	if sound.IsPlaying then
		sound:Pause()
		updateStatus("Pausado")
	elseif sound.SoundId ~= "" and sound.TimePosition > 0 then
		sound:Resume()
		updateStatus("Reproduciendo")
	else
		loadAndPlay()
	end
	setPlayGlyph()
end

-- Loads and plays a specific ID (from the menu lists).
-- If the ID belongs to the main list, syncs currentIndex
-- so prev/next continue from there.
local function findTrack(id)
	for _, t in ipairs(musicTracks) do
		if t.id == id then
			return t
		end
	end
	return nil
end

local function playId(id)
	for i, t in ipairs(musicTracks) do
		if t.id == id then
			currentIndex = i
			break
		end
	end
	currentTrackId = id
	loadAndPlay()
end

-- Current rows indexed by id (to highlight the playing one without rebuilding).
local rowsById = {}

local function makeRow(id, order)
	local trackInfo = findTrack(id)

	local rowBtn = Instance.new("TextButton")
	-- -10 leaves room on the right for the scroll bar (which would otherwise cover the ♥).
	rowBtn.Size = UDim2.new(1, -10, 0, 40)
	rowBtn.BackgroundColor3 = COLORS.field
	rowBtn.AutoButtonColor = true
	rowBtn.Text = ""
	rowBtn.LayoutOrder = order
	rowBtn.Parent = listScroll

	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(0, 6)
	rc.Parent = rowBtn

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -44, 0, 18)
	nameLabel.Position = UDim2.new(0, 10, 0, 4)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = trackInfo and trackInfo.name or id
	nameLabel.TextColor3 = COLORS.white
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Font = Enum.Font.GothamMedium
	nameLabel.TextSize = 13
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = rowBtn

	local subLabel = Instance.new("TextLabel")
	subLabel.Size = UDim2.new(1, -44, 0, 14)
	subLabel.Position = UDim2.new(0, 10, 0, 21)
	subLabel.BackgroundTransparency = 1
	subLabel.Text = trackInfo and trackSubtitle(trackInfo) or ("ID " .. id)
	subLabel.TextColor3 = COLORS.dim
	subLabel.TextXAlignment = Enum.TextXAlignment.Left
	subLabel.Font = Enum.Font.Gotham
	subLabel.TextSize = 11
	subLabel.TextTruncate = Enum.TextTruncate.AtEnd
	subLabel.Parent = rowBtn

	local mark = Instance.new("TextLabel")
	mark.Size = UDim2.fromOffset(24, 40)
	mark.Position = UDim2.new(1, -30, 0, 0)
	mark.BackgroundTransparency = 1
	mark.Text = isFavorite(id) and "♥" or ""
	mark.TextColor3 = COLORS.accent
	mark.Font = Enum.Font.GothamBold
	mark.TextSize = 14
	mark.Parent = rowBtn

	rowsById[id] = { button = rowBtn, sub = subLabel, mark = mark }

	rowBtn.MouseButton1Click:Connect(function()
		playId(id)
	end)

	return rowBtn
end

local function makeEmptyMessage(text)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 0, 40)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = COLORS.dim
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.TextWrapped = true
	lbl.Font = Enum.Font.Gotham
	lbl.TextSize = 12
	lbl.LayoutOrder = 1
	lbl.Parent = listScroll
end

local currentTab = "all"
local searchQuery = ""
-- Selected genre ("" = all).
local selectedGenre = ""

local function passesFilters(id)
	local t = findTrack(id)

	if selectedGenre ~= "" and (not t or t.genre ~= selectedGenre) then
		return false
	end

	if searchQuery ~= "" then
		local hay = id
		if t then
			hay = (t.name or "") .. " " .. (t.artist or "") .. " " .. (t.genre or "")
		end
		if not hay:lower():find(searchQuery, 1, true) then
			return false
		end
	end

	return true
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

	local source = (currentTab == "fav") and favorites or nil
	local order = 0
	if source then
		for _, id in ipairs(favorites) do
			if passesFilters(id) then
				order += 1
				makeRow(id, order)
			end
		end
	else
		for _, t in ipairs(musicTracks) do
			if passesFilters(t.id) then
				order += 1
				makeRow(t.id, order)
			end
		end
	end

	if order == 0 and (searchQuery ~= "" or selectedGenre ~= "") then
		makeEmptyMessage("Sin resultados con ese filtro.")
	end

	highlightCurrent()
end

highlightCurrent = function()
	local cur = currentId()
	for id, r in pairs(rowsById) do
		local sel = id == cur
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

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	searchQuery = searchBox.Text:lower()
	rebuildLists()
end)

-- Genre chips (radio). "Todos" (value "") + one chip per genre.
local genreChips = {}

local function styleGenreChips()
	for _, chip in ipairs(genreChips) do
		local active = chip.value == selectedGenre
		chip.button.BackgroundColor3 = active and COLORS.accent or COLORS.field
		chip.button.TextColor3 = active and COLORS.white or COLORS.dim
	end
end

local function makeGenreChip(label, value, order)
	local chip = Instance.new("TextButton")
	chip.Name = "Chip"
	chip.AutomaticSize = Enum.AutomaticSize.X
	chip.Size = UDim2.new(0, 0, 1, 0)
	chip.BackgroundColor3 = COLORS.field
	chip.AutoButtonColor = false
	chip.Text = label
	chip.TextColor3 = COLORS.dim
	chip.Font = Enum.Font.GothamMedium
	chip.TextSize = 12
	chip.LayoutOrder = order
	chip.Parent = genreScroll

	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 8)
	cc.Parent = chip

	local cp = Instance.new("UIPadding")
	cp.PaddingLeft = UDim.new(0, 12)
	cp.PaddingRight = UDim.new(0, 12)
	cp.Parent = chip

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

prevBtn.MouseButton1Click:Connect(function()
	currentIndex -= 1
	if currentIndex < 1 then
		currentIndex = #musicTracks
	end
	setCurrentId()
	loadAndPlay()
end)

local function playNext()
	currentIndex += 1
	if currentIndex > #musicTracks then
		currentIndex = 1
	end
	setCurrentId()
	loadAndPlay()
end

nextBtn.MouseButton1Click:Connect(playNext)

-- When the song ends, moves to the next one (doesn't repeat it).
sound.Ended:Connect(playNext)

playBtn.MouseButton1Click:Connect(togglePlay)

-- Heart = favorite of the current ID (toggle). State is per-song:
-- switching tracks recalculates it with refreshHeart().
heartBtn.MouseButton1Click:Connect(function()
	local id = currentId()
	if id == "" then
		return
	end
	if isFavorite(id) then
		removeFavorite(id)
	else
		addFavorite(id)
	end
	refreshHeart()
	rebuildLists()
end)

menuBtn.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible
end)

-- ================= Seek (progress bar) =================
local seeking = false

local function seekFromX(px)
	local rel = math.clamp((px - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
	fill.Size = UDim2.new(rel, 0, 1, 0)
	knob.Position = UDim2.new(rel, 0, 0.5, 0)
	if sound.TimeLength > 0 then
		sound.TimePosition = rel * sound.TimeLength
	end
end

seekHit.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		seeking = true
		seekFromX(input.Position.X)
	end
end)

trackConn(RunService.RenderStepped:Connect(function()
	if not seeking and sound.TimeLength > 0 then
		local rel = math.clamp(sound.TimePosition / sound.TimeLength, 0, 1)
		fill.Size = UDim2.new(rel, 0, 1, 0)
		knob.Position = UDim2.new(rel, 0, 0.5, 0)
	end
end))

-- ================= Dragging the whole bar (mouse + touch) =================
-- The bar background moves the widget; buttons/track consume their own input.
local dragging = false
local dragStart, startPos

bar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = bar.Position
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)

trackConn(UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch then
		local delta = input.Position - dragStart
		if dragging then
			bar.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		elseif seeking then
			seekFromX(input.Position.X)
		end
	end
end))

trackConn(UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
		seeking = false
	end
end))

loadFavorites()
setTab("all")
setCurrentId()
setPlayGlyph()
refreshHeart()

-- Cleanup for the next run: disconnects the service connections
-- and destroys this instance's UI + sound.
_G.MusicTesterCleanup = function()
	for _, conn in ipairs(uiConnections) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	pcall(function()
		sound:Destroy()
	end)
	pcall(function()
		screenGui:Destroy()
	end)
end
