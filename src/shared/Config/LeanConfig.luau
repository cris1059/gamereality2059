--!strict

-- Leaning (peeking round corners), shooter mode only. Q leans left, E right;
-- like a toggle: the same key straightens up, the other key switches sides.
-- The upper body rolls at the waist (the weapon and arms go with it), the
-- camera follows in both views, and the server rolls the hitboxes too
-- (Combat/LeanPose), so a lean really shows less of the body.

return table.freeze({
	LeftKeys = table.freeze({ Enum.KeyCode.Q, Enum.KeyCode.DPadLeft }),
	RightKeys = table.freeze({ Enum.KeyCode.E, Enum.KeyCode.DPadRight }),
	-- Upper-body roll at full lean (degrees, at the waist). First person the
	-- view rolls with the body about the same pivot, so the weapon keeps its
	-- place on screen.
	Degrees = 16,
	-- Share of that roll the neck takes back, so the head stays more level.
	NeckCounter = 0.3,
	-- Higher = faster into and out of a lean.
	BlendSpeed = 11,
	-- Third person: the camera moves this far to the lean side (studs) and
	-- rolls this much (degrees).
	ThirdPersonShift = 1.3,
	ThirdPersonRoll = 4,
})
