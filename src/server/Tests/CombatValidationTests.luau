--!strict
local Validator = require(script.Parent.Parent.Services.ShotValidator)
local RateLimiter = require(script.Parent.Parent.Services.RateLimiter)
local Tests = {}

function Tests.run(): {passed: number, total: number}
	local passed = 0
	local function check(value: boolean, message: string)
		assert(value, "Combat validation: " .. message)
		passed += 1
	end
	local function valid(origin: any, directions: any, time: any, pellets: number?): boolean
		return Validator.Validate(origin, directions, time, Vector3.zero, pellets or 1, 7)
	end
	check(valid(Vector3.zero, {Vector3.zAxis}, 100), "normal shot rejected")
	check(valid(Vector3.zero, table.create(8, Vector3.zAxis), 100, 8), "shotgun rejected")
	check(not valid(Vector3.new(8, 0, 0), {Vector3.zAxis}, 100), "distant origin accepted")
	check(not valid(Vector3.new(0/0, 0, 0), {Vector3.zAxis}, 100), "NaN origin accepted")
	check(not valid(Vector3.zero, {Vector3.new(math.huge, 0, 0)}, 100), "infinite direction accepted")
	check(not valid(Vector3.zero, {Vector3.zAxis}, 0/0), "NaN time accepted")
	check(not valid(Vector3.zero, {Vector3.zAxis}, math.huge), "infinite time accepted")
	check(not valid(Vector3.zero, {[1]=Vector3.zAxis, extra=Vector3.zAxis}, 100), "extra keyed pellet accepted")
	check(not valid(Vector3.zero, {[2]=Vector3.zAxis}, 100), "sparse array accepted")
	check(not valid(Vector3.zero, {Vector3.zero}, 100), "zero direction accepted")
	check(not valid(Vector3.zero, {"invalid"}, 100), "bad element accepted")
	check(not valid(Vector3.zero, {Vector3.zAxis * 100}, 100), "unnormalized direction accepted")
	check(not valid(Vector3.zero, table.create(9, Vector3.zAxis), 100, 8), "extra shotgun pellet accepted")
	local nextShot = Validator.NextShot(100, nil, 10)
	check(nextShot ~= nil and math.abs(nextShot - 100.1) < 1e-6, "wrong nominal cadence")
	check(Validator.NextShot(100.08, nextShot, 10) == nil, "25 percent faster cadence accepted")
	local early = Validator.NextShot(100.09, nextShot, 10)
	check(early ~= nil and math.abs(early - 100.2) < 1e-6, "jitter allowance accumulated")
	local clock = 0
	local limiter = RateLimiter.new(2, 1, function() return clock end)
	check(limiter:Allow(1) and limiter:Allow(1) and not limiter:Allow(1), "spam limit failed")
	clock = 1
	check(limiter:Allow(1), "limiter did not recover")
	limiter:Remove(1)
	check(limiter:Allow(1), "player cleanup failed")
	-- Exercise the production handler: invalid packets must not spend ammo
	-- or claim cooldowns, and a valid shot must spend exactly one round.
	local CombatService = require(script.Parent.Parent.Services.CombatService)
	local character = Instance.new("Model")
	local head = Instance.new("Part") head.Name = "Head" head.Parent = character
	local humanoid = Instance.new("Humanoid") humanoid.Parent = character
	local tool = Instance.new("Tool") tool:SetAttribute("LoadoutSlot", 1)
	tool:SetAttribute("WeaponClass", "rifle") tool:SetAttribute("Ammo", 10) tool.Parent = character
	local player: any = {UserId=987654321, Character=character}
	local service = setmetatable({
		_requestLimiter=RateLimiter.new(60,1), _nextShot={},
		_trace=function() return nil,nil,nil end,
		_shots={FireClient=function() end}, _hit={FireClient=function() end},
	}, CombatService)
	local ok, problem = pcall(function()
		service:_onFire(player, head.Position, {[1]=Vector3.zAxis, extra=Vector3.zAxis}, workspace:GetServerTimeNow())
		check(tool:GetAttribute("Ammo")==10 and service._nextShot[player]==nil, "invalid packet changed combat state")
		service:_onFire(player, head.Position, {Vector3.zAxis}, workspace:GetServerTimeNow())
		check(tool:GetAttribute("Ammo")==9 and service._nextShot[player]~=nil, "valid shot did not spend one round")
		service:_onFire(player, head.Position, {Vector3.zAxis}, workspace:GetServerTimeNow())
		check(tool:GetAttribute("Ammo")==9, "immediate repeated shot spent ammo")
		-- Draw time: a weapon just taken out cannot fire yet; once its draw
		-- time has passed it can.
		service._nextShot[player] = nil
		tool:SetAttribute("EquippedAt", workspace:GetServerTimeNow())
		service:_onFire(player, head.Position, {Vector3.zAxis}, workspace:GetServerTimeNow())
		check(tool:GetAttribute("Ammo")==9, "shot during the draw spent ammo")
		tool:SetAttribute("EquippedAt", workspace:GetServerTimeNow() - 5)
		service:_onFire(player, head.Position, {Vector3.zAxis}, workspace:GetServerTimeNow())
		check(tool:GetAttribute("Ammo")==8, "shot after the draw was refused")
	end)
	character:Destroy()
	assert(ok, tostring(problem))
	-- Lean hitboxes: the head goes out to the lean side and a little down,
	-- and no lean leaves it where it was.
	local LeanPose = require(game:GetService("ReplicatedStorage"):WaitForChild("CyberpunkOnline").Combat.LeanPose)
	local lowerTorso = CFrame.new(0, 3, 0)
	local headAt = CFrame.new(0, 4.8, 0)
	local function leanedHead(lean: number): Vector3
		return (LeanPose.upperBodyTransform(lowerTorso, Vector3.new(2, 0.4, 1), lean) * headAt).Position
	end
	check(leanedHead(1).X > 0.3 and leanedHead(1).Y < 4.8, "right lean did not move the head right and down")
	check(leanedHead(-1).X < -0.3, "left lean did not move the head left")
	check((leanedHead(0) - headAt.Position).Magnitude < 1e-6, "no lean moved the head")
	return {passed=passed, total=27}
end

return Tests
