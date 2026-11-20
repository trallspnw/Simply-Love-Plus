local index = Var("GameCommand"):GetIndex()
local choice_text = Var("GameCommand"):GetText()
local has_focus = false

local t = Def.ActorFrame{}

-- this renders the text of a single choice in the scroller
t[#t+1] = LoadFont("Common Bold")..{
	Name="Choice"..index,
	Text=THEME:GetString( 'ScreenTitleMenu', choice_text ),

	InitCommand=function(self) self:shadowlength(0.5) end,
	OnCommand=function(self) self:diffusealpha(0):sleep(index*0.075):linear(0.2):diffusealpha(1) end,
	OffCommand=function(self)
		-- when the chosen TitleMenu choice starts a game, broadcast using MESSAGEMAN
		-- actors can hook into these like
		-- TitleMenuToGameplayMessageCommand=function(self) end
		if has_focus and (choice_text == "Server Mode" or choice_text == "Dance Mode") then
			MESSAGEMAN:Broadcast("TitleMenuToGameplay")
		end
		if has_focus and choice_text == "Server Mode" then
			MESSAGEMAN:Broadcast("TitleMenuToServerMode")
		end

		self:sleep(index*0.075):linear(0.18):diffusealpha(0)
	end,
	VisualStyleSelectedMessageCommand=function(self)
		self:playcommand("UpdateColor")
	end,
	UpdateColorCommand=function(self)
		if has_focus then
			local textColor = PlayerColor(PLAYER_2)
			if ThemePrefs.Get("VisualStyle") == "SRPG9" then
				textColor = GetCurrentColor(true)
			end
			self:diffuse(textColor)
		else
			local textColor = color("#888888")
			if ThemePrefs.Get("RainbowMode") then
				textColor = Color.White
			end
			if ThemePrefs.Get("VisualStyle") == "SRPG9" then
				textColor = color(SL.SRPG9.TextColor)
			end
			self:diffuse(textColor)
		end
	end,

	GainFocusCommand=function(self)
		has_focus = true
		self:stoptweening():zoom(0.5)
		self:accelerate(0.1):glow(1,1,1,0.5)
		self:decelerate(0.05):glow(1,1,1,0)
		self:playcommand("UpdateColor")
	end,
	LoseFocusCommand=function(self)
		has_focus = false
		self:stoptweening():zoom(0.4)
		self:accelerate(0.1):glow(1,1,1,0)
		self:playcommand("UpdateColor")
	end
}

return t
