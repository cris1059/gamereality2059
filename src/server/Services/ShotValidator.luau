--!strict

-- Bounded, side-effect-free validation before ammo, cooldowns or raycasts.
local ShotValidator = {}

function ShotValidator.IsFinite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function finiteVector(value: any): boolean
	return typeof(value) == "Vector3" and ShotValidator.IsFinite(value.X)
		and ShotValidator.IsFinite(value.Y) and ShotValidator.IsFinite(value.Z)
end

function ShotValidator.Validate(origin: any, directions: any, shotTime: any, head: Vector3, pellets: number, tolerance: number): boolean
	if not finiteVector(origin) or not ShotValidator.IsFinite(shotTime) or type(directions) ~= "table" then
		return false
	end
	if (origin - head).Magnitude > tolerance then return false end
	local count = 0
	for key, direction in directions do
		count += 1
		if count > pellets or type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > pellets then
			return false
		end
		if not finiteVector(direction) then return false end
		local magnitude = direction.Magnitude
		if not ShotValidator.IsFinite(magnitude) or magnitude < 0.5 or magnitude > 1.5 then return false end
	end
	return count == pellets
end

-- Small scheduling allowance, never compounded into a higher sustained rate.
function ShotValidator.NextShot(now: number, nextShot: number?, fireRate: number): number?
	if nextShot and now + 0.015 < nextShot then return nil end
	return math.max(now, nextShot or now) + 1 / fireRate
end

return ShotValidator
