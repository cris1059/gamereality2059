--!strict

-- Closed testing. While Enabled, a PUBLISHED server removes every player who
-- is not on the list (Studio is never restricted). Off by default: Roblox's
-- own privacy (a Private experience, or a group-owned one) is the first line;
-- this is a second one for when the experience has to be visible.

return table.freeze({
	Enabled = false,
	-- Roblox user ids allowed to play (the experience owner always is).
	UserIds = table.freeze({}) :: { number },
	-- Optional: members of this group (at or above MinRank) are allowed too.
	GroupId = 0,
	MinRank = 1,
	KickMessage = "REALITY 2059 está en pruebas cerradas. Pide a quien te invitó que te agregue a la lista.",
})
