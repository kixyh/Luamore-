--[[
	JOBLESS LOADER v3  |  Rayfield-style loading screen + key system
	Edit CONFIG below, put your real script in CONFIG.OnSuccess.
	Features: draggable window, minimize/close, staggered page animations,
	toast notifications, attempt pips, saved keys, optional remote key list.
]]

local CONFIG = {
	Title = "Jobless",
	Subtitle = "Hub",
	Version = "v1.0",
	Note = "Press Get Key to copy the link, open it in your browser, complete the steps, then paste your key here.",
	GetKeyLink = "https://YOUR-PROJECT.vercel.app/",       -- page where users generate their key
	ValidateURL = "https://YOUR-PROJECT.vercel.app/api/check?key=", -- server checks the key; key is appended
	SendUserId = true,                                 -- also sends &uid=<UserId> so keys can be bound to a player
	DiscordLink = "https://discord.gg/yourinvite",
	SaveFile = "JoblessKey.txt",
	MaxAttempts = 5,
	CooldownSeconds = 15,
	Accent = Color3.fromRGB(0, 146, 214),              -- Rayfield default blue
	LoadSteps = {
		{ "Initializing...", 0.12 },
		{ "Checking environment...", 0.28 },
		{ "Loading modules...", 0.50 },
		{ "Connecting to services...", 0.72 },
		{ "Preparing interface...", 0.90 },
		{ "Ready!", 1.00 },
	},
	Tips = {
		"Tip: Drag the top bar to move this window.",
		"Tip: Your key is saved after the first login.",
		"Tip: Join the Discord for updates and support.",
		"Tip: Press Enter in the key box to verify.",
	},
	OnSuccess = function()
		-- PUT YOUR REAL SCRIPT HERE. Example:
		-- loadstring(game:HttpGet("https://your-site.com/main.lua"))()
		print("[Jobless] Key accepted - main script runs here")
	end,
}

----------------------------------------------------------------------
-- Services / theme / helpers
----------------------------------------------------------------------
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local lp = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G
if env.JoblessLoaderCleanup then pcall(env.JoblessLoaderCleanup) end

local T = { -- Rayfield "Default" theme
	bg = Color3.fromRGB(25, 25, 25),
	top = Color3.fromRGB(34, 34, 34),
	elem = Color3.fromRGB(35, 35, 35),
	elemHover = Color3.fromRGB(44, 44, 44),
	stroke = Color3.fromRGB(50, 50, 50),
	inputStroke = Color3.fromRGB(75, 75, 75),
	text = Color3.fromRGB(240, 240, 240),
	sub = Color3.fromRGB(165, 165, 165),
	dim = Color3.fromRGB(110, 110, 110),
	good = Color3.fromRGB(70, 210, 125),
	bad = Color3.fromRGB(240, 85, 85),
	warn = Color3.fromRGB(240, 175, 65),
	discord = Color3.fromRGB(88, 101, 242),
}
local ACCENT = CONFIG.Accent
local ACCENT_LIGHT = ACCENT:Lerp(Color3.new(1, 1, 1), 0.3)

local Q, QIN, BACK, LIN = Enum.EasingStyle.Quint, Enum.EasingDirection.In, Enum.EasingStyle.Back, Enum.EasingStyle.Linear

local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props) do i[k] = v end
	i.Parent = parent
	return i
end

local function corner(i, r, isScale)
	return new("UICorner", { CornerRadius = isScale and UDim.new(r, 0) or UDim.new(0, r or 8) }, i)
end

local function tween(obj, t, props, style, dir)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end

local function label(parent, props)
	local d = { BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextColor3 = T.text, TextSize = 13, Text = "" }
	for k, v in pairs(props) do d[k] = v end
	return new("TextLabel", d, parent)
end

local function getParent()
	local ok, h = pcall(function() return gethui and gethui() end)
	if ok and h then return h end
	local ok2, cg = pcall(function() return game:GetService("CoreGui") end)
	if ok2 and cg then
		local t = Instance.new("Folder")
		local ok3 = pcall(function() t.Parent = cg end)
		t:Destroy()
		if ok3 then return cg end
	end
	return lp:WaitForChild("PlayerGui")
end

-- Asks your server whether the key is valid.
-- Returns true (valid), false (invalid) or nil (could not reach the server).
-- Your endpoint should reply with plain "true"/"false" or JSON like {"valid":true}.
local function checkKey(key)
	local url = CONFIG.ValidateURL .. HttpService:UrlEncode(key)
	if CONFIG.SendUserId then url ..= "&uid=" .. lp.UserId end
	local ok, res = pcall(function() return game:HttpGet(url) end)
	if not ok or type(res) ~= "string" then return nil end
	res = trim(res)
	if res:lower() == "true" then return true end
	local ok2, data = pcall(function() return HttpService:JSONDecode(res) end)
	if ok2 and type(data) == "table" and data.valid == true then return true end
	return false
end

local state = {
	remember = true, attempts = 0, locked = false, busy = false, boxState = "idle",
	closed = false, closing = false, minimized = false, size = Vector2.new(440, 230),
}
local function dead() return state.closed or state.closing end

----------------------------------------------------------------------
-- Root GUI, frame updater, cleanup
----------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "JoblessLoader"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
if syn and syn.protect_gui then pcall(syn.protect_gui, gui) end
gui.Parent = getParent()

local conns = {}
local updaters = {}
local function onFrame(fn) table.insert(updaters, fn) end
table.insert(conns, RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	for _, fn in ipairs(updaters) do fn(dt, t) end
end))

env.JoblessLoaderCleanup = function()
	state.closed = true
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	pcall(function() gui:Destroy() end)
	env.JoblessLoaderCleanup = nil
end

local baseScale
do
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(900, 600)
	baseScale = math.clamp(math.min(vp.X / 480, vp.Y / 420, 1), 0.55, 1)
end

local dim = new("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1,
	BorderSizePixel = 0, ZIndex = 1,
}, gui)

----------------------------------------------------------------------
-- Notifications (Rayfield-style toasts, bottom right)
----------------------------------------------------------------------
local notifHolder = new("Frame", {
	AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -18), Size = UDim2.new(0, 300, 1, -36),
	BackgroundTransparency = 1, ZIndex = 50,
}, gui)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical, VerticalAlignment = Enum.VerticalAlignment.Bottom,
	HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 8),
}, notifHolder)

local notifCount = 0
local function notify(title, content, kind, dur)
	if state.closed then return end
	dur = dur or 3.5
	notifCount += 1
	local col = (kind == "ok" and T.good) or (kind == "err" and T.bad) or (kind == "warn" and T.warn) or ACCENT
	local holder = new("Frame", {
		Size = UDim2.new(1, 0, 0, 62), BackgroundTransparency = 1, LayoutOrder = notifCount, ZIndex = 50,
	}, notifHolder)
	local card = new("Frame", {
		Size = UDim2.fromScale(1, 1), Position = UDim2.new(1, 60, 0, 0), BackgroundColor3 = T.top,
		BorderSizePixel = 0, ZIndex = 51,
	}, holder)
	corner(card, 8)
	new("UIStroke", { Color = T.stroke, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
	local bar = new("Frame", {
		Position = UDim2.fromOffset(8, 10), Size = UDim2.new(0, 3, 1, -20), BackgroundColor3 = col,
		BorderSizePixel = 0, ZIndex = 52,
	}, card)
	corner(bar, 2)
	label(card, {
		Position = UDim2.fromOffset(20, 8), Size = UDim2.new(1, -30, 0, 16), Text = title,
		Font = Enum.Font.GothamBold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 52,
	})
	label(card, {
		Position = UDim2.fromOffset(20, 25), Size = UDim2.new(1, -30, 0, 28), Text = content, TextSize = 12,
		TextColor3 = T.sub, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 52,
	})
	local line = new("Frame", {
		Position = UDim2.new(0, 12, 1, -5), Size = UDim2.new(1, -24, 0, 2), BackgroundColor3 = col,
		BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 52,
	}, card)
	corner(line, 1)
	tween(card, 0.5, { Position = UDim2.fromScale(0, 0) }, BACK)
	tween(line, dur, { Size = UDim2.new(0, 0, 0, 2) }, LIN)
	task.delay(dur, function()
		if not card.Parent then return end
		tween(card, 0.35, { Position = UDim2.new(1, 60, 0, 0) }, Q, QIN)
		task.wait(0.4)
		holder:Destroy()
	end)
end

----------------------------------------------------------------------
-- Window (stage > shadow + main canvas + outline)
----------------------------------------------------------------------
local stage = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(440, 230),
	BackgroundTransparency = 1, ZIndex = 5,
}, gui)
local stageScale = new("UIScale", { Scale = baseScale * 0.88 }, stage)

local shadow = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 8), Size = UDim2.new(1, 36, 1, 36),
	BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1,
}, stage)
corner(shadow, 22)

local main = new("CanvasGroup", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.bg, BorderSizePixel = 0, GroupTransparency = 1, ZIndex = 2,
}, stage)
corner(main, 8)

local outline = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3 }, stage)
corner(outline, 8)
local outlineStroke = new("UIStroke", {
	Thickness = 1, Color = T.stroke, Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, outline)

-- top bar
local topbar = new("Frame", {
	Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = T.top, BorderSizePixel = 0, ZIndex = 3,
}, main)
new("Frame", {
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1),
	BackgroundColor3 = T.stroke, BorderSizePixel = 0, ZIndex = 4,
}, topbar)

local dot = new("Frame", {
	AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.5, 0), Size = UDim2.fromOffset(8, 8),
	BackgroundColor3 = ACCENT, BorderSizePixel = 0, ZIndex = 4,
}, topbar)
corner(dot, 0.5, true)
onFrame(function(_, t) dot.BackgroundTransparency = 0.05 + (math.sin(t * 3) + 1) * 0.22 end)

local left = new("Frame", {
	Position = UDim2.fromOffset(32, 0), Size = UDim2.new(0.6, 0, 1, 0), BackgroundTransparency = 1, ZIndex = 4,
}, topbar)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8),
}, left)
label(left, {
	AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), Text = CONFIG.Title .. " " .. CONFIG.Subtitle,
	Font = Enum.Font.GothamSemibold, TextSize = 14, ZIndex = 4, LayoutOrder = 1,
})
local chip = new("Frame", {
	AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 18), BackgroundColor3 = T.elem,
	BorderSizePixel = 0, ZIndex = 4, LayoutOrder = 2,
}, left)
corner(chip, 5)
new("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }, chip)
label(chip, {
	AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), Text = CONFIG.Version, TextSize = 10,
	TextColor3 = T.sub, Font = Enum.Font.GothamSemibold, ZIndex = 5,
})

local function iconButton(pos, hoverCol)
	local b = new("TextButton", {
		Text = "", AutoButtonColor = false, Size = UDim2.fromOffset(28, 28), Position = pos,
		BackgroundColor3 = hoverCol, BackgroundTransparency = 1, ZIndex = 5,
	}, topbar)
	corner(b, 6)
	b.MouseEnter:Connect(function() tween(b, 0.15, { BackgroundTransparency = 0.7 }) end)
	b.MouseLeave:Connect(function() tween(b, 0.15, { BackgroundTransparency = 1 }) end)
	return b
end
local function iconLine(parent, w, rot)
	local l = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(w, 2),
		Rotation = rot, BackgroundColor3 = T.sub, BorderSizePixel = 0, ZIndex = 6,
	}, parent)
	corner(l, 1)
end
local closeBtn = iconButton(UDim2.new(1, -36, 0, 6), T.bad)
iconLine(closeBtn, 12, 45)
iconLine(closeBtn, 12, -45)
local minBtn = iconButton(UDim2.new(1, -68, 0, 6), T.elemHover)
iconLine(minBtn, 11, 0)

-- dragging
do
	local dragging, dragStart, startPos
	topbar.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, startPos = true, i.Position, stage.Position
			i.Changed:Connect(function()
				if i.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	table.insert(conns, UserInputService.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - dragStart
			stage.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end))
end

local body = new("Frame", {
	Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40), BackgroundTransparency = 1, ZIndex = 3,
}, main)

----------------------------------------------------------------------
-- Pages + staggered section animations
----------------------------------------------------------------------
local function newPage()
	return { frame = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, body), secs = {} }
end

local function sec(page, pos, size)
	local s = new("CanvasGroup", {
		Position = pos, Size = size, BackgroundTransparency = 1, GroupTransparency = 1, BorderSizePixel = 0,
	}, page.frame)
	table.insert(page.secs, { obj = s, pos = pos })
	return s
end

local function showPage(p)
	p.frame.Visible = true
	for i, s in ipairs(p.secs) do
		s.obj.GroupTransparency = 1
		s.obj.Position = s.pos + UDim2.fromOffset(0, 14)
		task.delay((i - 1) * 0.05, function()
			tween(s.obj, 0.45, { GroupTransparency = 0, Position = s.pos }, Q)
		end)
	end
end

local function hidePage(p)
	for _, s in ipairs(p.secs) do
		tween(s.obj, 0.18, { GroupTransparency = 1, Position = s.pos - UDim2.fromOffset(0, 8) })
	end
	task.delay(0.2, function() p.frame.Visible = false end)
end

local currentPage
local function setSize(w, h)
	state.size = Vector2.new(w, h)
	if not state.minimized then
		tween(stage, 0.5, { Size = UDim2.fromOffset(w, h) }, Q)
	end
end

local function goto(page, w, h)
	local first = currentPage == nil
	if currentPage and currentPage ~= page then hidePage(currentPage) end
	currentPage = page
	setSize(w, h)
	if not first then task.wait(0.25) end
	showPage(page)
end

local function makeButton(parent, text, bg, hoverBg, size, pos, textColor)
	local b = new("TextButton", {
		Text = text, Size = size, Position = pos, BackgroundColor3 = bg, TextColor3 = textColor or T.text,
		Font = Enum.Font.GothamSemibold, TextSize = 13, AutoButtonColor = false, BorderSizePixel = 0, ZIndex = 8,
	}, parent)
	corner(b, 6)
	local sc = new("UIScale", { Scale = 1 }, b)
	b.MouseEnter:Connect(function() tween(b, 0.15, { BackgroundColor3 = hoverBg }) end)
	b.MouseLeave:Connect(function()
		tween(b, 0.15, { BackgroundColor3 = bg })
		tween(sc, 0.12, { Scale = 1 })
	end)
	b.MouseButton1Down:Connect(function() tween(sc, 0.08, { Scale = 0.96 }) end)
	b.MouseButton1Up:Connect(function() tween(sc, 0.15, { Scale = 1 }, BACK) end)
	return b
end

----------------------------------------------------------------------
-- LOADING PAGE
----------------------------------------------------------------------
local L = newPage()
local ui = {}

do
	local s = sec(L, UDim2.fromOffset(24, 26), UDim2.new(1, -48, 0, 62))
	label(s, {
		Size = UDim2.new(1, 0, 0, 34), Text = string.upper(CONFIG.Title .. " " .. CONFIG.Subtitle),
		Font = Enum.Font.GothamBlack, TextSize = 28,
	})
	label(s, {
		Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 18), Text = "Preparing your experience",
		TextColor3 = T.sub, TextSize = 13,
	})
end

do
	local s = sec(L, UDim2.fromOffset(32, 106), UDim2.new(1, -64, 0, 40))
	local barBg = new("Frame", {
		Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = T.elem, BorderSizePixel = 0,
	}, s)
	corner(barBg, 0.5, true)
	ui.fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.white or Color3.new(1, 1, 1), BorderSizePixel = 0 }, barBg)
	corner(ui.fill, 0.5, true)
	local g = new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, ACCENT), ColorSequenceKeypoint.new(0.5, ACCENT_LIGHT), ColorSequenceKeypoint.new(1, ACCENT),
		}),
	}, ui.fill)
	onFrame(function(_, t) g.Offset = Vector2.new(math.sin(t * 2.2) * 0.4, 0) end)
	ui.status = label(s, {
		Position = UDim2.fromOffset(0, 16), Size = UDim2.new(0.7, 0, 0, 18), Text = "Starting...",
		TextSize = 12, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Left,
	})
	ui.pct = label(s, {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 16), Size = UDim2.fromOffset(60, 18), Text = "0%",
		Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = ACCENT, TextXAlignment = Enum.TextXAlignment.Right,
	})
end

do
	local s = sec(L, UDim2.fromOffset(24, 156), UDim2.new(1, -48, 0, 20))
	ui.tip = label(s, {
		Size = UDim2.fromScale(1, 1), Text = CONFIG.Tips[1] or "", TextSize = 12, TextColor3 = T.dim,
	})
end

----------------------------------------------------------------------
-- KEY PAGE
----------------------------------------------------------------------
local K = newPage()

do
	local s = sec(K, UDim2.fromOffset(24, 16), UDim2.new(1, -48, 0, 46))
	label(s, {
		Size = UDim2.new(1, 0, 0, 24), Text = "Key System", Font = Enum.Font.GothamBold, TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	label(s, {
		Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 16), Text = "Enter your key to unlock " .. CONFIG.Title,
		TextSize = 12, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Left,
	})
end

do -- note card
	local s = sec(K, UDim2.fromOffset(24, 68), UDim2.new(1, -48, 0, 40))
	local f = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.elem, BorderSizePixel = 0 }, s)
	corner(f, 6)
	local bar = new("Frame", {
		Position = UDim2.fromOffset(8, 9), Size = UDim2.new(0, 3, 1, -18), BackgroundColor3 = ACCENT, BorderSizePixel = 0,
	}, f)
	corner(bar, 2)
	label(f, {
		Position = UDim2.fromOffset(20, 0), Size = UDim2.new(1, -28, 1, 0), Text = CONFIG.Note, TextSize = 12,
		TextColor3 = T.sub, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
	})
end

do -- input
	local s = sec(K, UDim2.fromOffset(22, 116), UDim2.new(1, -44, 0, 46))
	ui.inputFrame = new("Frame", {
		Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 1, -4), BackgroundColor3 = T.elem, BorderSizePixel = 0,
	}, s)
	corner(ui.inputFrame, 6)
	ui.inputStroke = new("UIStroke", {
		Thickness = 1.5, Color = T.inputStroke, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, ui.inputFrame)
	ui.box = new("TextBox", {
		Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -140, 1, 0), BackgroundTransparency = 1,
		PlaceholderText = "Enter key...", PlaceholderColor3 = T.dim, Text = "", ClearTextOnFocus = false,
		Font = Enum.Font.GothamMedium, TextSize = 14, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 9,
	}, ui.inputFrame)
	ui.pasteBtn = makeButton(ui.inputFrame, "Paste", T.top, T.elemHover, UDim2.fromOffset(52, 28), UDim2.new(1, -114, 0.5, -14))
	ui.clearBtn = makeButton(ui.inputFrame, "Clear", T.top, T.elemHover, UDim2.fromOffset(52, 28), UDim2.new(1, -58, 0.5, -14))
	ui.pasteBtn.TextSize, ui.clearBtn.TextSize = 12, 12
end

local pips = {}
do -- status + attempt pips
	local s = sec(K, UDim2.fromOffset(24, 170), UDim2.new(1, -48, 0, 18))
	ui.keyStatus = label(s, {
		Size = UDim2.new(1, -80, 1, 0), TextSize = 12, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Left,
	})
	local holder = new("Frame", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(120, 18),
		BackgroundTransparency = 1,
	}, s)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 5),
	}, holder)
	for i = 1, CONFIG.MaxAttempts do
		local p = new("Frame", {
			Size = UDim2.fromOffset(8, 8), BackgroundColor3 = T.stroke, BorderSizePixel = 0, LayoutOrder = i,
		}, holder)
		corner(p, 0.5, true)
		pips[i] = p
	end
end

local track, knob, toggleHit
do -- remember toggle
	local s = sec(K, UDim2.fromOffset(24, 196), UDim2.new(1, -48, 0, 24))
	toggleHit = new("TextButton", {
		Size = UDim2.fromOffset(190, 24), BackgroundTransparency = 1, Text = "", ZIndex = 9,
	}, s)
	track = new("Frame", {
		Position = UDim2.fromOffset(0, 2), Size = UDim2.fromOffset(40, 20), BackgroundColor3 = ACCENT, BorderSizePixel = 0, ZIndex = 9,
	}, toggleHit)
	corner(track, 0.5, true)
	knob = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 22, 0.5, 0), Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 10,
	}, track)
	corner(knob, 0.5, true)
	label(toggleHit, {
		Position = UDim2.fromOffset(50, 0), Size = UDim2.new(1, -50, 1, 0), Text = "Remember my key", TextSize = 13,
		TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9,
	})
end

do -- buttons
	local s = sec(K, UDim2.fromOffset(24, 228), UDim2.new(1, -48, 0, 40))
	ui.verify = makeButton(s, "Verify Key", ACCENT, ACCENT_LIGHT, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Color3.new(1, 1, 1))
	ui.verify.TextSize = 14
	local s2 = sec(K, UDim2.fromOffset(24, 276), UDim2.new(1, -48, 0, 34))
	ui.getKey = makeButton(s2, "Get Key", T.elem, T.elemHover, UDim2.new(0.5, -4, 1, 0), UDim2.fromScale(0, 0))
	ui.discord = makeButton(s2, "Discord", T.discord, T.discord:Lerp(Color3.new(1, 1, 1), 0.15), UDim2.new(0.5, -4, 1, 0), UDim2.new(0.5, 4, 0, 0), Color3.new(1, 1, 1))
	local s3 = sec(K, UDim2.fromOffset(24, 316), UDim2.new(1, -48, 0, 14))
	label(s3, {
		Size = UDim2.fromScale(1, 1), Text = "Press Enter to verify  •  Your key is saved after the first login",
		TextSize = 10, TextColor3 = T.dim,
	})
end

----------------------------------------------------------------------
-- SUCCESS PAGE
----------------------------------------------------------------------
local S = newPage()
do
	local s = sec(S, UDim2.fromOffset(0, 20), UDim2.new(1, 0, 0, 100))
	ui.okRing = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
	}, s)
	corner(ui.okRing, 0.5, true)
	new("UIStroke", { Thickness = 4, Color = T.good }, ui.okRing)
	ui.okMark = label(ui.okRing, {
		Size = UDim2.fromScale(1, 1), Text = "✓", Font = Enum.Font.GothamBlack, TextSize = 40,
		TextColor3 = T.good, TextTransparency = 1,
	})
	local s2 = sec(S, UDim2.fromOffset(0, 126), UDim2.new(1, 0, 0, 28))
	label(s2, {
		Size = UDim2.fromScale(1, 1), Text = "ACCESS GRANTED", Font = Enum.Font.GothamBlack, TextSize = 22, TextColor3 = T.good,
	})
	local s3 = sec(S, UDim2.fromOffset(0, 156), UDim2.new(1, 0, 0, 18))
	label(s3, { Size = UDim2.fromScale(1, 1), Text = "Welcome, " .. lp.DisplayName, TextColor3 = T.sub })
end

----------------------------------------------------------------------
-- Loading logic
----------------------------------------------------------------------
local loadingActive = true
task.spawn(function() -- rotating tips
	local i = 1
	while loadingActive and not dead() do
		task.wait(2.4)
		if not loadingActive or dead() or #CONFIG.Tips == 0 then break end
		tween(ui.tip, 0.25, { TextTransparency = 1 })
		task.wait(0.28)
		i = i % #CONFIG.Tips + 1
		ui.tip.Text = CONFIG.Tips[i]
		tween(ui.tip, 0.25, { TextTransparency = 0 })
	end
end)

local function runLoading()
	local shown = 0
	for _, step in ipairs(CONFIG.LoadSteps) do
		if dead() then return end
		ui.status.Text = step[1]
		local dur = 0.35 + math.random() * 0.4
		tween(ui.fill, dur, { Size = UDim2.fromScale(step[2], 1) }, Q)
		local target = math.floor(step[2] * 100)
		local s0, t0 = shown, os.clock()
		while true do
			local a = math.clamp((os.clock() - t0) / dur, 0, 1)
			shown = math.floor(s0 + (target - s0) * a)
			ui.pct.Text = shown .. "%"
			if a >= 1 or dead() then break end
			task.wait()
		end
		task.wait(0.1 + math.random() * 0.22)
	end
	loadingActive = false
	task.wait(0.35)
end

----------------------------------------------------------------------
-- Key logic
----------------------------------------------------------------------
local function readSavedKey()
	if type(isfile) == "function" and type(readfile) == "function" then
		local ok, res = pcall(function()
			if isfile(CONFIG.SaveFile) then return readfile(CONFIG.SaveFile) end
		end)
		if ok and res and res ~= "" then return trim(res) end
	end
end
local function saveKey(k)
	if type(writefile) == "function" then pcall(writefile, CONFIG.SaveFile, k) end
end
local function clearSavedKey()
	if type(delfile) == "function" and type(isfile) == "function" then
		pcall(function() if isfile(CONFIG.SaveFile) then delfile(CONFIG.SaveFile) end end)
	elseif type(writefile) == "function" then
		pcall(writefile, CONFIG.SaveFile, "")
	end
end

local function setStatus(msg, kind)
	local col = (kind == "ok" and T.good) or (kind == "err" and T.bad) or (kind == "warn" and T.warn) or T.sub
	ui.keyStatus.Text = msg ~= "" and ("●  " .. msg) or ""
	ui.keyStatus.TextColor3 = col
end

local function setBoxState(s)
	state.boxState = s
	local col = (s == "focus" and ACCENT) or (s == "err" and T.bad) or (s == "ok" and T.good) or T.inputStroke
	tween(ui.inputStroke, 0.2, { Color = col })
end

local function setPips()
	for i, p in ipairs(pips) do
		tween(p, 0.25, { BackgroundColor3 = i <= state.attempts and T.bad or T.stroke })
	end
end

ui.box.Focused:Connect(function() if state.boxState ~= "ok" then setBoxState("focus") end end)

toggleHit.MouseButton1Click:Connect(function()
	state.remember = not state.remember
	tween(track, 0.18, { BackgroundColor3 = state.remember and ACCENT or T.stroke })
	tween(knob, 0.25, { Position = state.remember and UDim2.new(0, 22, 0.5, 0) or UDim2.new(0, 2, 0.5, 0) }, BACK)
end)

ui.pasteBtn.MouseButton1Click:Connect(function()
	if type(getclipboard) == "function" then
		local ok, text = pcall(getclipboard)
		if ok and text then
			ui.box.Text = trim(text)
			setStatus("Pasted from clipboard.", "ok")
			return
		end
	end
	setStatus("Clipboard not supported. Paste manually.", "warn")
	notify("Clipboard unavailable", "Your executor doesn't support getclipboard.", "warn")
end)
ui.clearBtn.MouseButton1Click:Connect(function()
	ui.box.Text = ""
	setStatus("", "info")
	setBoxState("idle")
end)

local function copyLink(link, okMsg)
	if type(setclipboard) == "function" then
		pcall(setclipboard, link)
		setStatus(okMsg, "ok")
		notify("Copied", okMsg, "ok")
	else
		setStatus(link, "info")
		notify("Clipboard unavailable", link, "info", 6)
	end
end
ui.getKey.MouseButton1Click:Connect(function() copyLink(CONFIG.GetKeyLink, "Key link copied to clipboard!") end)
ui.discord.MouseButton1Click:Connect(function() copyLink(CONFIG.DiscordLink, "Discord invite copied!") end)

local function shake()
	local origin = stage.Position
	for i = 1, 6 do
		local off = (i % 2 == 0 and 1 or -1) * (13 - i * 1.7)
		tween(stage, 0.04, { Position = origin + UDim2.fromOffset(off, 0) })
		task.wait(0.045)
	end
	tween(stage, 0.06, { Position = origin })
end

local function fadeOutAll(t)
	tween(main, t, { GroupTransparency = 1 })
	tween(shadow, t, { BackgroundTransparency = 1 })
	tween(outlineStroke, t, { Transparency = 1 })
	tween(dim, t + 0.1, { BackgroundTransparency = 1 })
end

local function finish()
	state.busy = true
	local onSuccess = CONFIG.OnSuccess
	hidePage(K)
	setSize(440, 230)
	task.wait(0.3)
	showPage(S)
	task.wait(0.3)
	tween(ui.okRing, 0.55, { Size = UDim2.fromOffset(76, 76) }, BACK)
	task.wait(0.3)
	tween(ui.okMark, 0.3, { TextTransparency = 0 })
	notify("Access granted", "Loading " .. CONFIG.Title .. " " .. CONFIG.Subtitle .. "...", "ok", 2.5)
	task.wait(1.1)
	tween(stageScale, 0.45, { Scale = baseScale * 1.08 }, Enum.EasingStyle.Quad, QIN)
	fadeOutAll(0.4)
	task.wait(0.6)
	if state.closed or state.closing then return end
	env.JoblessLoaderCleanup()
	task.spawn(onSuccess)
end

local function startCooldown()
	state.locked = true
	notify("Too many attempts", "Locked for " .. CONFIG.CooldownSeconds .. " seconds.", "warn", 4)
	task.spawn(function()
		for s = CONFIG.CooldownSeconds, 1, -1 do
			if dead() then return end
			setStatus("Too many attempts. Wait " .. s .. "s", "warn")
			ui.verify.Text = "Locked (" .. s .. "s)"
			task.wait(1)
		end
		state.attempts, state.locked = 0, false
		setPips()
		ui.verify.Text = "Verify Key"
		setStatus("You can try again.", "info")
	end)
end

local function verify(key, auto)
	if state.busy or state.locked or dead() then return end
	key = trim(key)
	if key == "" then
		setStatus("Please enter a key.", "warn")
		notify("Missing key", "Paste or type your key first.", "warn")
		return
	end
	state.busy = true
	setStatus("Checking key...", "info")
	ui.verify.Text = "Checking..."
	local valid = checkKey(key)
	task.wait(0.3)
	if dead() then return end
	if valid == nil then
		state.busy = false
		ui.verify.Text = "Verify Key"
		setStatus("Could not reach the key server.", "warn")
		notify("Connection error", "Couldn't reach the key server. Try again.", "warn")
		return
	end
	if valid then
		ui.verify.Text = "Verified!"
		setBoxState("ok")
		setStatus("Key accepted!", "ok")
		if state.remember then saveKey(key) else clearSavedKey() end
		task.wait(0.5)
		finish()
	else
		state.busy = false
		ui.verify.Text = "Verify Key"
		if auto then clearSavedKey() end
		state.attempts += 1
		setPips()
		setBoxState("err")
		local left = math.max(CONFIG.MaxAttempts - state.attempts, 0)
		setStatus("Invalid key. (" .. left .. " tries left)", "err")
		notify("Invalid key", left .. " attempts remaining.", "err")
		task.spawn(shake)
		task.delay(1.3, function()
			if not dead() and state.boxState == "err" then setBoxState("idle") end
		end)
		if state.attempts >= CONFIG.MaxAttempts then startCooldown() end
	end
end

ui.verify.MouseButton1Click:Connect(function() verify(ui.box.Text, false) end)
ui.box.FocusLost:Connect(function(enter)
	if state.boxState == "focus" then setBoxState("idle") end
	if enter then verify(ui.box.Text, false) end
end)

----------------------------------------------------------------------
-- Window controls
----------------------------------------------------------------------
minBtn.MouseButton1Click:Connect(function()
	state.minimized = not state.minimized
	local h = state.minimized and 40 or state.size.Y
	tween(stage, 0.4, { Size = UDim2.fromOffset(state.size.X, h) }, Q)
end)

closeBtn.MouseButton1Click:Connect(function()
	if state.closing then return end
	state.closing = true
	tween(stageScale, 0.35, { Scale = baseScale * 0.9 }, Q, QIN)
	fadeOutAll(0.3)
	task.wait(0.45)
	if env.JoblessLoaderCleanup then env.JoblessLoaderCleanup() end
end)

----------------------------------------------------------------------
-- RUN
----------------------------------------------------------------------
task.spawn(function()
	tween(dim, 0.6, { BackgroundTransparency = 0.45 })
	tween(main, 0.5, { GroupTransparency = 0 })
	tween(shadow, 0.6, { BackgroundTransparency = 0.6 })
	tween(outlineStroke, 0.5, { Transparency = 0 })
	tween(stageScale, 0.7, { Scale = baseScale }, BACK)
	goto(L, 440, 230)

	runLoading()
	if dead() then return end

	local saved = readSavedKey()
	goto(K, 440, 374)
	task.wait(0.4)
	if dead() then return end
	setStatus("Waiting for your key...", "info")

	if saved then
		ui.box.Text = saved
		setStatus("Saved key found. Logging in...", "ok")
		notify("Welcome back", "Saved key found, logging you in.", "info", 2.5)
		task.wait(0.8)
		verify(saved, true)
	end
end)
