-- this difficulty grid doesn't support CourseMode
-- CourseContentsList.lua should be used instead
if GAMESTATE:IsCourseMode() then return end
-- ----------------------------------------------

local GetStepsToDisplay = LoadActor("./StepsToDisplay.lua")
local meter_height = 28
local meter_spacing = 2
local name_width = 78
local meter_width = 30
local column_gap = 2
local total_width = name_width + meter_width + column_gap

local name_box_x = -((meter_width + column_gap) / 2)
local meter_box_x = ((name_width + column_gap) / 2)

local DifficultyLabel = function(difficulty)
	if not difficulty then return "" end
	return THEME:GetString("Difficulty", ToEnumShortString(difficulty))
end

local t = Def.ActorFrame{
	Name="StepsDisplayList",
	InitCommand=function(self) self:xy(_screen.cx-34, _screen.cy + 67) end,

	OnCommand=function(self)                           self:queuecommand("RedrawStepsDisplay") end,
	CurrentSongChangedMessageCommand=function(self)    self:queuecommand("RedrawStepsDisplay") end,
	CurrentStepsP1ChangedMessageCommand=function(self) self:queuecommand("RedrawStepsDisplay") end,
	CurrentStepsP2ChangedMessageCommand=function(self) self:queuecommand("RedrawStepsDisplay") end,

	RedrawStepsDisplayCommand=function(self)

		local song = GAMESTATE:GetCurrentSong()

		if song then
			local steps = SongUtil.GetPlayableSteps( song )

			if steps then
				local StepsToDisplay = GetStepsToDisplay(steps)

				for i=1,5 do
					if StepsToDisplay[i] then
						-- if this particular song has a stepchart for this row, update the Meter
						-- and BlockRow coloring appropriately
						local meter = StepsToDisplay[i]:GetMeter()
						local difficulty = StepsToDisplay[i]:GetDifficulty()
						self:GetChild("Grid"):GetChild("Name_"..i):playcommand("Set",   {Meter=meter, Difficulty=difficulty})
						self:GetChild("Grid"):GetChild("Meter_"..i):playcommand("Set",  {Meter=meter, Difficulty=difficulty})
					else
						-- otherwise, set the meter to an empty string and hide this particular colored BlockRow
						self:GetChild("Grid"):GetChild("Name_"..i):playcommand("Unset")
						self:GetChild("Grid"):GetChild("Meter_"..i):playcommand("Unset")
					end
				end
			end
		else
			self:playcommand("Unset")
		end
	end,
}

t[#t+1] = Def.Quad{
	Name="Background",
	InitCommand=function(self)
		self:diffuse(color("#1e282f")):zoomto(total_width + 4, 152)
		if ThemePrefs.Get("RainbowMode") then
			self:diffusealpha(0.9)
		end
		if ThemePrefs.Get("VisualStyle") == "Technique" then
			self:diffusealpha(0.5)
		end
	end
}

local Grid = Def.ActorFrame{
	Name="Grid",
	InitCommand=function(self) end,
}

for RowNumber=-2, 2 do
	Grid[#Grid+1] = Def.Quad{
		Name="NameBackground_"..(RowNumber + 3),
		InitCommand=function(self)
			self:diffuse(color("#0f0f0f"))
				:zoomto(name_width, meter_height)
				:x(name_box_x)
				:y((meter_height + meter_spacing) * RowNumber)
			if ThemePrefs.Get("RainbowMode") then
				self:diffusealpha(0.9)
			end
		end
	}

	Grid[#Grid+1] = Def.Quad{
		Name="MeterBackground_"..(RowNumber + 3),
		InitCommand=function(self)
			self:diffuse(color("#0f0f0f"))
				:zoomto(meter_width, meter_height)
				:x(meter_box_x)
				:y((meter_height + meter_spacing) * RowNumber)
			if ThemePrefs.Get("RainbowMode") then
				self:diffusealpha(0.9)
			end
		end
	}

	Grid[#Grid+1] = LoadFont("Common Bold")..{
		Name="Name_"..(RowNumber + 3),
		InitCommand=function(self)
			self:x(name_box_x):y((meter_height + meter_spacing) * RowNumber):zoom(0.4):maxwidth(180)
		end,
		SetCommand=function(self, params)
			self:diffuse( DifficultyColor(params.Difficulty) )
			self:settext(DifficultyLabel(params.Difficulty))
		end,
		UnsetCommand=function(self) self:settext(""):diffuse(color("#182025")) end,
	}

	Grid[#Grid+1] = LoadFont("Common Bold")..{
		Name="Meter_"..(RowNumber + 3),
		InitCommand=function(self)
			self:x(meter_box_x):y((meter_height + meter_spacing) * RowNumber):zoom(0.45)
		end,
		SetCommand=function(self, params)
			-- diffuse and set each chart's difficulty meter
			self:diffuse( DifficultyColor(params.Difficulty) )
			self:settext(tostring(params.Meter or "?"))
		end,
		UnsetCommand=function(self) self:settext(""):diffuse(color("#182025")) end,
	}
end

t[#t+1] = Grid

return t
