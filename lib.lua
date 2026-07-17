--[[
	ryshub/music lib.lua — shared UI / input / HTTP / icon helpers.
	Generic (no player logic), reusable by other ryshub scripts.
]]

local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local Lib = {}

-- ================= Connections =================

-- Global (non-UI-tree) connections created through Lib.track; a re-run calls
-- Lib.cleanup() to disconnect them all.
local connections = {}

function Lib.track(conn)
	table.insert(connections, conn)
	return conn
end

function Lib.cleanup()
	for _, conn in ipairs(connections) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	table.clear(connections)
end

-- ================= HTTP =================

-- Fetches a URL trying every HTTP API the executor may expose.
function Lib.fetch(url)
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

-- Downloads and executes a Lua module, returning its result (or nil).
function Lib.fetchModule(url)
	local src = Lib.fetch(url)
	if not src then
		return nil
	end
	local ok, result = pcall(function()
		return loadstring(src)()
	end)
	return ok and result or nil
end

-- ================= Instance helpers =================

-- Declarative Instance builder; `Parent` is applied last.
function Lib.create(className, props)
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		if key ~= "Parent" then
			inst[key] = value
		end
	end
	inst.Parent = props.Parent
	return inst
end

function Lib.corner(parent, radiusPx)
	return Lib.create("UICorner", {
		CornerRadius = radiusPx and UDim.new(0, radiusPx) or UDim.new(1, 0),
		Parent = parent,
	})
end

function Lib.padding(parent, top, bottom, left, right)
	return Lib.create("UIPadding", {
		PaddingTop = UDim.new(0, top or 0),
		PaddingBottom = UDim.new(0, bottom or 0),
		PaddingLeft = UDim.new(0, left or 0),
		PaddingRight = UDim.new(0, right or 0),
		Parent = parent,
	})
end

-- ================= Input =================

Lib.TAP_THRESHOLD = 6 -- px of movement before a press counts as a drag

function Lib.isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

function Lib.isMove(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
end

-- Makes `target` follow pointer drags that start on `handle`. If `onTap` is
-- given, a press-release without real movement fires it instead.
function Lib.makeDraggable(handle, target, onTap)
	local dragging = false
	local moved = false
	local pressAt, startPos

	handle.InputBegan:Connect(function(input)
		if Lib.isPress(input) then
			dragging = true
			moved = false
			pressAt = input.Position
			startPos = target.Position
		end
	end)

	Lib.track(UserInputService.InputChanged:Connect(function(input)
		if dragging and Lib.isMove(input) then
			local delta = input.Position - pressAt
			if delta.Magnitude > Lib.TAP_THRESHOLD then
				moved = true
			end
			target.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end))

	Lib.track(UserInputService.InputEnded:Connect(function(input)
		if dragging and Lib.isPress(input) then
			dragging = false
			if onTap and not moved then
				onTap()
			end
		end
	end))
end

-- Slider plumbing: a press on `hit` starts dragging and `apply(position)`
-- runs on every pointer move until release. Returns an isDragging() probe.
function Lib.makeSlider(hit, apply)
	local dragging = false

	hit.InputBegan:Connect(function(input)
		if Lib.isPress(input) then
			dragging = true
			apply(input.Position)
		end
	end)

	Lib.track(UserInputService.InputChanged:Connect(function(input)
		if dragging and Lib.isMove(input) then
			apply(input.Position)
		end
	end))

	Lib.track(UserInputService.InputEnded:Connect(function(input)
		if Lib.isPress(input) then
			dragging = false
		end
	end))

	return function()
		return dragging
	end
end

-- ================= Icons =================

-- Icon system backed by Footagesus' icon module, downloaded on demand and
-- cached (shared with other scripts through _G.Lucide). Every icon has a
-- text-glyph fallback for when the module can't load.
local Icons = {
	url = nil,
	pack = "lucide",
	module = nil,
}
Lib.icons = Icons

function Icons.configure(url, pack)
	Icons.url = url
	Icons.pack = pack or Icons.pack
end

local function getModule()
	if Icons.module then
		return Icons.module
	end
	if type(_G) == "table" and _G.Lucide then
		Icons.module = _G.Lucide
		return Icons.module
	end
	if not Icons.url then
		return nil
	end
	local mod = Lib.fetchModule(Icons.url)
	if mod then
		Icons.module = mod
		_G.Lucide = mod
	end
	return Icons.module
end

-- Resolves an icon to { Image, ImageRectOffset, ImageRectSize } or nil.
-- Always requests the explicit pack so it doesn't depend on the default type
-- another script might have set.
local function readAsset(name)
	local lucide = getModule()
	if not lucide or not name then
		return nil
	end

	local data
	for _, fnName in ipairs({ "Icon2", "Icon" }) do
		if type(lucide[fnName]) == "function" then
			local ok, res = pcall(lucide[fnName], name, Icons.pack, true)
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

	local set = lucide.Icons and lucide.Icons[Icons.pack]
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

function Icons.apply(imageObject, name)
	local asset = readAsset(name)
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

-- Icon display (image + text fallback) centered in `parent`.
-- `set(name, glyph)` swaps the icon, `tint(color)` recolors both layers.
function Icons.createIcon(parent, size, color, fallbackTextSize)
	local img = Lib.create("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		ImageColor3 = color,
		Parent = parent,
	})
	local fb = Lib.create("TextLabel", {
		Name = "Fallback",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = color,
		Font = Enum.Font.GothamBold,
		TextSize = fallbackTextSize or math.floor(size * 0.9),
		Visible = false,
		Parent = parent,
	})

	local ctl = {}
	function ctl.set(iconName, glyph)
		if glyph then
			fb.Text = glyph
		end
		local ok = Icons.apply(img, iconName)
		img.Visible = ok
		fb.Visible = not ok
	end
	function ctl.tint(c)
		img.ImageColor3 = c
		fb.TextColor3 = c
	end
	return ctl
end

return Lib
