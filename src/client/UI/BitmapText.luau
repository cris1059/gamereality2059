--!strict

local BitmapText = {}

local function splitLines(value: string): { string }
	local lines = {}
	for line in string.gmatch(value .. "\n", "(.-)\n") do
		table.insert(lines, string.upper(line))
	end
	return lines
end

local function bindLabel(label: TextLabel | TextButton, typography)
	local atlasId = typography.BitmapAtlasId
	if type(atlasId) ~= "string" or atlasId == "" then
		return
	end
	if label:FindFirstChild("BlankaBitmapText") then
		return
	end

	local characters = typography.BitmapCharacters
	local columns = typography.BitmapColumns
	local cellSize = typography.BitmapCellSize
	local indexByCharacter = {}
	for index = 1, #characters do
		indexByCharacter[string.sub(characters, index, index)] = index - 1
	end

	local originalTransparency = label.TextTransparency
	label.TextTransparency = 1

	local container = Instance.new("Frame")
	container.Name = "BlankaBitmapText"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.ClipsDescendants = false
	container.ZIndex = label.ZIndex + 1
	container.Parent = label

	local rebuilding = false
	local function rebuild()
		if rebuilding or not label.Parent then
			return
		end
		rebuilding = true
		container:ClearAllChildren()
		local lines = splitLines(label.Text)
		local lineCount = math.max(#lines, 1)
		local longest = 1
		for _, line in lines do
			longest = math.max(longest, #line)
		end
		local available = label.AbsoluteSize
		local glyphHeight = if label.TextScaled
			then math.clamp(math.min(available.Y / lineCount, available.X / (longest * 0.72)), 8, 160)
			else label.TextSize
		-- Preserve the square atlas cell so BLANKA is never horizontally
		-- compressed. Advance cells overlap only their transparent margins.
		local glyphWidth = glyphHeight
		local glyphAdvance = glyphHeight * 0.72
		local totalHeight = glyphHeight * lineCount
		local yStart = if label.TextYAlignment == Enum.TextYAlignment.Top then 0
			elseif label.TextYAlignment == Enum.TextYAlignment.Bottom then available.Y - totalHeight
			else (available.Y - totalHeight) * 0.5

		for lineIndex, line in lines do
			local rowWidth = if #line > 0 then (#line - 1) * glyphAdvance + glyphWidth else 0
			local xStart = if label.TextXAlignment == Enum.TextXAlignment.Left then 0
				elseif label.TextXAlignment == Enum.TextXAlignment.Right then available.X - rowWidth
				else (available.X - rowWidth) * 0.5
			for characterIndex = 1, #line do
				local character = string.sub(line, characterIndex, characterIndex)
				local atlasIndex = indexByCharacter[character]
				if atlasIndex then
					local glyph = Instance.new("ImageLabel")
					glyph.Name = "Glyph"
					glyph.BackgroundTransparency = 1
					glyph.Size = UDim2.fromOffset(glyphWidth, glyphHeight)
					glyph.Position = UDim2.fromOffset(xStart + (characterIndex - 1) * glyphAdvance, yStart + (lineIndex - 1) * glyphHeight)
					glyph.Image = atlasId
					glyph.ImageRectOffset = Vector2.new((atlasIndex % columns) * cellSize, math.floor(atlasIndex / columns) * cellSize)
					glyph.ImageRectSize = Vector2.new(cellSize, cellSize)
					glyph.ImageColor3 = label.TextColor3
					glyph.ImageTransparency = originalTransparency
					glyph.ScaleType = Enum.ScaleType.Fit
					glyph.ZIndex = container.ZIndex
					glyph.Parent = container
					if label:GetAttribute("BlankaGlow") == true then
						local glow = glyph:Clone()
						glow.Name = "Glow"
						glow.Position = glyph.Position + UDim2.fromOffset(2, 2)
						glow.ImageColor3 = Color3.fromRGB(255, 45, 146)
						glow.ImageTransparency = 0.62
						glow.ZIndex = container.ZIndex
						glow.Parent = container
						glyph.ZIndex = container.ZIndex + 1
					end
				end
			end
		end
		rebuilding = false
	end

	label:GetPropertyChangedSignal("Text"):Connect(rebuild)
	label:GetPropertyChangedSignal("TextColor3"):Connect(rebuild)
	label:GetPropertyChangedSignal("TextSize"):Connect(rebuild)
	label:GetPropertyChangedSignal("AbsoluteSize"):Connect(rebuild)
	task.defer(rebuild)
end

function BitmapText.BindTree(root: Instance, typography)
	for _, descendant in root:GetDescendants() do
		if (descendant:IsA("TextLabel") or descendant:IsA("TextButton")) and descendant.Font == typography.Display then
			bindLabel(descendant, typography)
		end
	end
end

return BitmapText
