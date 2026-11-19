--!strict
-- Provisional engine-bundled audio; replace with approved game-owned assets
-- after an in-game listening pass. No external asset uploads are needed.
return table.freeze({
	Enabled = true,
	Shot = table.freeze({id="rbxasset://sounds/impact_explosion_03.mp3", volume=0.12, speed=1.7, maxDistance=140}),
	Hit = table.freeze({id="rbxasset://sounds/volume_slider.ogg", volume=0.35, speed=1.5}),
	-- Reload (ReloadAnimation): magazine out / seated, charging handle back / home.
	MagOut = table.freeze({id="rbxasset://sounds/volume_slider.ogg", volume=0.45, speed=0.75}),
	MagIn = table.freeze({id="rbxasset://sounds/action_jump_land.mp3", volume=0.55, speed=2.4}),
	BoltBack = table.freeze({id="rbxasset://sounds/volume_slider.ogg", volume=0.5, speed=0.55}),
	BoltRelease = table.freeze({id="rbxasset://sounds/impact_explosion_03.mp3", volume=0.08, speed=3.2}),
	-- Slide (SlideEffects): a thump dropping into it and a scrape that follows
	-- the speed. Engine sounds for now; swap in game-owned ones.
	SlideStart = table.freeze({id="rbxasset://sounds/action_jump_land.mp3", volume=0.55, speed=0.8, maxDistance=70}),
	SlideScrape = table.freeze({id="rbxasset://sounds/action_falling.ogg", volume=0.35, speed=1.7, maxDistance=70}),
	-- Per-weapon shots (Tool name). `single`: every shot heard by others, and
	-- the first shot of each trigger pull. `auto` (automatic weapons): a loop
	-- recorded at `rpm` shots a minute that plays while the trigger stays held,
	-- slowed or sped up to the weapon's real fire rate (so its pitch moves a
	-- little; keepPitch = true corrects it at the cost of some latency).
	-- Weapons not listed use Shot.
	-- Distant echo of gunfire, any weapon (CombatController:_echo). Others'
	-- shots: a 3D echo from the shooter that takes over from the direct shot
	-- with distance (nearShare of `volume` next to them, all of it from
	-- farDistance on), reaching up to maxDistance and arriving late by the
	-- speed of sound. Your own shots: a soft echo of the surroundings.
	-- At most one echo per shooter every minInterval seconds (held fire).
	Echo = table.freeze({
		id = "rbxassetid://102361061255237", -- VK7_Distant_Gunshot (recorded very quietly: the volumes make up for it)
		volume = 7,
		nearShare = 0.25,
		nearDistance = 30,
		farDistance = 220,
		maxDistance = 1500,
		ownVolume = 2.5,
		ownDelay = 0.08,
		minInterval = 0.3,
		studsPerSecond = 1225, -- 343 m/s with 1 stud = 0.28 m
	}),
	-- `voices`: how many of the weapon's single shots may ring at once (its
	-- tail length x fire rate); `duck`: share of volume earlier tails keep
	-- when a new shot fires, so held fire stays clear instead of piling up.
	Weapons = table.freeze({
		["R2059 Rifle VK-7"] = table.freeze({
			-- Single_gunshot_from__#4 (0.8 s, starts at 0 ms, ~0.7 s natural tail).
			-- Every round plays it, held fire included: same sound start to end.
			-- (Previous: Neon_AK_Single_v4 103591626222440 + bursts below.)
			single = table.freeze({id="rbxassetid://75243054078308", volume=0.6, speed=1, maxDistance=160, voices=8, duck=0.45}),
			-- The weapon's own reload sound ("recarga vk7", 2.08 s), played from
			-- the start of every reload; it replaces the generic MagOut / MagIn /
			-- Bolt cues. `marks`: seconds into the sound of its main clacks, and
			-- the reload animation (ReloadAnimation) is re-timed so the hand
			-- pulls the magazine, seats the new one and works the charging
			-- handle exactly on them. (Uploaded as VK7_Recarga; Roblox censored
			-- its name, so it does not show up by name in inventory searches.)
			reload = table.freeze({
				id = "rbxassetid://70688665442401",
				volume = 0.8,
				maxDistance = 80,
				marks = table.freeze({ magOut = 0.53, magIn = 1.0, boltBack = 1.21, boltRelease = 1.32 }),
			}),
			-- The burst re-timed to the VK-7's own 480 rpm (from the 600 rpm
			-- recording, 135704268365384), so it loops at normal speed: same pitch
			-- as the single shot, no pitch shifting, no delay. v4 (115502877743148)
			-- left a near-silent gap after every shot; v5 overlaps each shot's
			-- natural decay. The bursts were made from Neon_AK_Single_v4, so they
			-- no longer match the new single shot; a burst loop for it would need
			-- re-making from the new sound. Not used:
			-- auto = table.freeze({id="rbxassetid://130380364793156", volume=0.6, rpm=480, maxDistance=160}), -- Neon_AK_Burst_480RPM_v5
		}),
	}),
})
