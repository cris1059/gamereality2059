--!strict

-- Shared day/night clock (FreeRoamConfig.DayCycle). Day (NightEnd ->
-- NightStart) lasts DaySeconds of real time and night lasts NightSeconds, so
-- each half can be tuned on its own. Server and clients use the same maths
-- with the server epoch, so everyone sees the same hour.

local DayCycle = {}

local function spans(cycle)
	local dayHours = (cycle.NightStart - cycle.NightEnd) % 24
	return dayHours, 24 - dayHours
end

-- Real seconds per full cycle.
function DayCycle.Length(cycle): number
	return cycle.DaySeconds + cycle.NightSeconds
end

-- Clock time (0..24) after `elapsed` real seconds since the epoch.
function DayCycle.ClockAt(cycle, elapsed: number): number
	if type(cycle.FixedClockTime) == "number" then
		return cycle.FixedClockTime % 24
	end
	local dayHours, nightHours = spans(cycle)
	local t = elapsed % DayCycle.Length(cycle)
	if t < cycle.DaySeconds then
		return (cycle.NightEnd + t / cycle.DaySeconds * dayHours) % 24
	end
	return (cycle.NightStart + (t - cycle.DaySeconds) / cycle.NightSeconds * nightHours) % 24
end

-- Real seconds into the cycle at which the clock shows `clock`.
function DayCycle.ElapsedFor(cycle, clock: number): number
	local dayHours, nightHours = spans(cycle)
	local intoDay = (clock - cycle.NightEnd) % 24
	if intoDay < dayHours then
		return intoDay / dayHours * cycle.DaySeconds
	end
	return cycle.DaySeconds + (intoDay - dayHours) / nightHours * cycle.NightSeconds
end

function DayCycle.IsNight(cycle, clock: number): boolean
	return (clock - cycle.NightEnd) % 24 >= (cycle.NightStart - cycle.NightEnd) % 24
end

return DayCycle
