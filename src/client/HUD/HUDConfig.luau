--!strict

-- Every look-and-feel number of the combat HUD in one place: palette, layout,
-- health thresholds, portrait states, animation timings. Components read
-- this; nothing visual is hard-coded elsewhere.

local HUDConfig = {}

HUDConfig.Palette = table.freeze({
	Carbon = Color3.fromHex("090D14"),
	Metal = Color3.fromHex("202938"),
	MetalLight = Color3.fromHex("2E3A4E"),
	Electric = Color3.fromHex("18C8FF"),
	Cyan = Color3.fromHex("00E5FF"),
	White = Color3.fromHex("EAF7FF"),
	Muted = Color3.fromHex("8FA9C0"),
	Violet = Color3.fromHex("A04DFF"),
	Danger = Color3.fromHex("FF365E"),
	Warning = Color3.fromHex("FF974A"),
	Amber = Color3.fromHex("FFC24A"),
	Enemy = Color3.fromHex("FF6D84"),
})

HUDConfig.Fonts = table.freeze({
	Display = Enum.Font.SciFi, -- numbers and titles
	Interface = Enum.Font.Jura, -- names, labels
	Technical = Enum.Font.Code, -- small tags
})

-- The HUD is drawn in design pixels for this height and scaled to the
-- screen (UIScale), within these limits (960: a little over 1:1 at 1080p).
HUDConfig.DesignHeight = 960
HUDConfig.MinScale = 0.6
HUDConfig.MaxScale = 1.6
-- Distance kept from the screen edges (design pixels), inside the safe area.
HUDConfig.Margin = 28

HUDConfig.Health = table.freeze({
	Segments = 12,
	-- Colour bands by health fraction (above Caution = healthy).
	Caution = 0.6,
	Critical = 0.25,
	-- Seconds: the bar follows quickly, the "lost health" ghost waits, then drains.
	FollowTime = 0.18,
	GhostDelay = 0.45,
	GhostDrain = 0.5,
	HealFlashTime = 0.6,
})

-- Portrait states. Gloat needs a kill streak inside StreakWindow seconds and
-- lasts GloatSeconds (refreshed by each further kill).
HUDConfig.Portrait = table.freeze({
	GloatStreak = 3,
	StreakWindow = 12,
	GloatSeconds = 8,
	TransitionTime = 0.35,
	-- Optional portrait art per class: { normal = "rbxassetid://...",
	-- gloat = "...", critical = "..." }. Empty: a live 3D bust of the
	-- player's own avatar is used. Never put placeholder ids here.
	Images = table.freeze({}) :: { [string]: { normal: string?, gloat: string?, critical: string? } },
})

HUDConfig.Ammo = table.freeze({
	-- Below this share of the magazine the count turns to a warning.
	Low = 0.3,
	FireKickTime = 0.08,
	SwitchSlideTime = 0.22,
})

HUDConfig.KillFeed = table.freeze({
	MaxEntries = 4,
	Seconds = 5,
})

HUDConfig.Crosshair = table.freeze({
	Gap = 7,
	Length = 7,
	-- Extra gap per shot (design pixels), recovering at RecoverSpeed per second.
	ShotSpread = 5,
	MaxSpread = 18,
	RecoverSpeed = 40,
	HitTime = 0.15,
	KillTime = 0.35,
})

return HUDConfig
