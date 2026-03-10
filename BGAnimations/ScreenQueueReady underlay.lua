local TARGET_SONG_DIR = "songs/1arc1998 - ddr [i]/butterfly/"
local PLACEHOLDER_USER = "Username_placeholder"

local top_screen
local target_song
local available_steps = {}
local selected_index = 1
local showing_exit_confirm = false
local exit_choice_yes = true
local last_up_press = 0
local last_down_press = 0
local double_tap_window = 0.33
local input

local is_start_button = function(event)
	local game_button = event and event.GameButton or ""
	local menu_button = event and event.MenuButton or ""
	local button = tostring(event and event.button or ""):lower()
	local device_button = tostring(event and event.DeviceInput and event.DeviceInput.button or ""):lower()
	return game_button == "Start"
		or game_button == "Center"
		or game_button == "Select"
		or menu_button == "Start"
		or menu_button == "Center"
		or menu_button == "Select"
		or button:find("enter", 1, true) ~= nil
		or button:find("return", 1, true) ~= nil
		or device_button:find("enter", 1, true) ~= nil
		or device_button:find("return", 1, true) ~= nil
end

local is_back_button = function(event)
	local game_button = event and event.GameButton or ""
	local menu_button = event and event.MenuButton or ""
	local button = tostring(event and event.button or ""):lower()
	local device_button = tostring(event and event.DeviceInput and event.DeviceInput.button or ""):lower()
	return game_button == "Back"
		or menu_button == "Back"
		or button:find("escape", 1, true) ~= nil
		or button == "esc"
		or device_button:find("escape", 1, true) ~= nil
end

local normalize = function(path)
	return (path or ""):gsub("\\", "/"):lower()
end

local find_target_song = function()
	local songs = SONGMAN:GetAllSongs() or {}
	for song in ivalues(songs) do
		local dir = normalize(song:GetSongDir())
		if dir:find(TARGET_SONG_DIR, 1, true) then
			return song
		end
	end
	return nil
end

local sort_by_difficulty = function(a, b)
	return Difficulty:Reverse()[a:GetDifficulty()] < Difficulty:Reverse()[b:GetDifficulty()]
end

local get_steps_for_current_style = function(song)
	local style = GAMESTATE:GetCurrentStyle()
	if not style or not song then return {} end

	local steps_type = style:GetStepsType()
	local steps = song:GetStepsByStepsType(steps_type) or {}
	local filtered = {}

	for chart in ivalues(steps) do
		if chart:GetDifficulty() ~= "Difficulty_Edit" then
			filtered[#filtered+1] = chart
		end
	end

	table.sort(filtered, sort_by_difficulty)
	return filtered
end

local apply_selected_chart = function()
	if not target_song or #available_steps == 0 then return end

	local steps = available_steps[selected_index]
	if not steps then return end

	GAMESTATE:SetCurrentSong(target_song)

	for pn in ivalues(GAMESTATE:GetHumanPlayers()) do
		GAMESTATE:SetCurrentSteps(pn, steps)
		GAMESTATE:SetPreferredDifficulty(pn, steps:GetDifficulty())
	end
end

local ensure_steps_available = function()
	if target_song and #available_steps == 0 then
		available_steps = get_steps_for_current_style(target_song)
	end
end

local transition_to = function(screen_name)
	if not top_screen then return end
	if type(input) == "function" then
		top_screen:RemoveInputCallback(input)
	end
	top_screen:SetNextScreenName(screen_name)
	top_screen:StartTransitioningScreen("SM_GoToNextScreen")
end

local update_view = function(frame)
	local user_text = frame:GetChild("UsernameText")
	local song_text = frame:GetChild("SongText")
	local artist_text = frame:GetChild("ArtistText")
	local error_text = frame:GetChild("ErrorText")
	local prompt_text = frame:GetChild("PromptText")
	local exit_overlay = frame:GetChild("ExitConfirm")
	local exit_choice = exit_overlay and exit_overlay:GetChild("ChoiceText")

	if not target_song then
		error_text:settext(THEME:GetString("ScreenQueueReady", "MissingSong"):format(TARGET_SONG_DIR))
		user_text:settext("")
		song_text:settext("")
		artist_text:settext("")
		return
	end

	local subtitle = target_song:GetDisplaySubTitle() or ""
	local title = target_song:GetDisplayMainTitle() or ""
	if subtitle ~= "" then
		title = title .. "\n" .. subtitle
	end

	error_text:settext("")
	user_text:settext(PLACEHOLDER_USER)
	song_text:settext(title)
	artist_text:settext(target_song:GetDisplayArtist() or "")

	if prompt_text then
		prompt_text:zoom(0.75)
	end

	if exit_overlay and exit_choice then
		exit_overlay:visible(showing_exit_confirm)
		exit_choice:settext(exit_choice_yes and "Yes" or "No")
	end
end

input = function(event)
	if not event or event.type == "InputEventType_Release" then return false end

	if showing_exit_confirm then
		if event.GameButton == "MenuLeft" or event.GameButton == "MenuRight" then
			exit_choice_yes = not exit_choice_yes
			local snd = top_screen:GetChild("Underlay") and top_screen:GetChild("Underlay"):GetChild("change_sound")
			if snd then snd:play() end
			top_screen:GetChild("Underlay"):playcommand("Refresh")
			return true
		end

			if is_start_button(event) then
				if exit_choice_yes then
					local snd = top_screen:GetChild("Underlay") and top_screen:GetChild("Underlay"):GetChild("start_sound")
					if snd then snd:play() end
					SL.Global.QueueModeActive = false
					transition_to("ScreenTitleMenu")
				else
					showing_exit_confirm = false
				local snd = top_screen:GetChild("Underlay") and top_screen:GetChild("Underlay"):GetChild("change_sound")
				if snd then snd:play() end
				top_screen:GetChild("Underlay"):playcommand("Refresh")
			end
			return true
		end

		if is_back_button(event) then
			showing_exit_confirm = false
			local snd = top_screen:GetChild("Underlay") and top_screen:GetChild("Underlay"):GetChild("change_sound")
			if snd then snd:play() end
			top_screen:GetChild("Underlay"):playcommand("Refresh")
			return true
		end
	end

	if event.GameButton == "MenuUp" then
		local now = GetTimeSinceStart()
		if #available_steps > 0 and (now - last_up_press) <= double_tap_window then
			selected_index = ((selected_index - 2) % #available_steps) + 1
			apply_selected_chart()
			top_screen:GetChild("Underlay"):playcommand("Refresh")
			local snd = top_screen:GetChild("Underlay") and top_screen:GetChild("Underlay"):GetChild("change_sound")
			if snd then snd:play() end
		end
		last_up_press = now
		return true
	end

	if event.GameButton == "MenuDown" then
		local now = GetTimeSinceStart()
		if #available_steps > 0 and (now - last_down_press) <= double_tap_window then
			selected_index = (selected_index % #available_steps) + 1
			apply_selected_chart()
			top_screen:GetChild("Underlay"):playcommand("Refresh")
			local snd = top_screen:GetChild("Underlay") and top_screen:GetChild("Underlay"):GetChild("change_sound")
			if snd then snd:play() end
		end
		last_down_press = now
		return true
	end

	if is_start_button(event) then
		if GAMESTATE:GetNumSidesJoined() == 0 then
			local joined = event.PlayerNumber and GAMESTATE:JoinInput(event.PlayerNumber)
			if not joined then
				GAMESTATE:JoinPlayer(PLAYER_1)
			end
		end

		ensure_steps_available()

		if target_song and #available_steps > 0 then
			apply_selected_chart()
			local snd = top_screen:GetChild("Underlay") and top_screen:GetChild("Underlay"):GetChild("start_sound")
			if snd then snd:play() end
			-- Match the stable gameplay transition path used by other custom select flows.
			GAMESTATE:SetCurrentPlayMode("PlayMode_Regular")
			local song_options = GAMESTATE:GetSongOptionsObject("ModsLevel_Preferred")
			if song_options then
				song_options:MusicRate(SL.Global.ActiveModifiers.MusicRate)
			end
			-- Run gameplay/eval with ITG string lookups while preserving queue loop flow.
			SL.Global.QueueModeActive = true
			SL.Global.GameMode = "ITG"
			transition_to("ScreenGameplay")
		else
			SCREENMAN:SystemMessage("Queue mode could not start (missing player or chart).")
		end
		return true
	end

	if is_back_button(event) then
		showing_exit_confirm = true
		exit_choice_yes = true
		local snd = top_screen:GetChild("Underlay") and top_screen:GetChild("Underlay"):GetChild("change_sound")
		if snd then snd:play() end
		top_screen:GetChild("Underlay"):playcommand("Refresh")
		return true
	end

	return false
end

local t = Def.ActorFrame{
	OnCommand=function(self)
		top_screen = SCREENMAN:GetTopScreen()
		SL.Global.QueueModeActive = true
		-- Keep Queue mode in a valid playmode for gameplay startup.
		GAMESTATE:SetCurrentPlayMode("PlayMode_Regular")
		local song_options = GAMESTATE:GetSongOptionsObject("ModsLevel_Preferred")
		if song_options then
			song_options:MusicRate(SL.Global.ActiveModifiers.MusicRate)
		end

		if GAMESTATE:GetNumSidesJoined() == 0 then
			GAMESTATE:JoinPlayer(PLAYER_1)
		end

		target_song = find_target_song()
		available_steps = get_steps_for_current_style(target_song)
		selected_index = 1
		showing_exit_confirm = false
		exit_choice_yes = true
		last_up_press = 0
		last_down_press = 0

		apply_selected_chart()
		self:playcommand("Refresh")

		if top_screen then
			top_screen:AddInputCallback(input)
		end
	end,

	OffCommand=function(self)
		if top_screen then
			top_screen:RemoveInputCallback(input)
		end
	end,

	RefreshCommand=function(self)
		update_view(self)
	end,

	Def.Quad{
		InitCommand=function(self)
			self:Center():zoomto(620, 160):diffuse(color("#000000")):diffusealpha(0.65):y(-100)
		end
	},

	LoadFont("Common Bold")..{
		Name="PromptText",
		Text=THEME:GetString("ScreenQueueReady", "ReadyPrompt"),
		InitCommand=function(self)
			self:xy(_screen.cx, _screen.cy - 150):zoom(0.75)
		end
	},

	Def.Quad{
		Name="UsernameBox",
		InitCommand=function(self)
			self:xy(_screen.cx + 240, _screen.cy + 2):zoomto(360, 34):diffuse(color("#000000")):diffusealpha(0.45)
		end
	},

	Def.Quad{
		Name="SongArtistBox",
		InitCommand=function(self)
			self:xy(_screen.cx + 240, _screen.cy + 94):zoomto(360, 134):diffuse(color("#000000")):diffusealpha(0.45)
		end
	},

	LoadFont("Common Normal")..{
		Name="UsernameText",
		InitCommand=function(self)
			self:xy(_screen.cx + 70, _screen.cy + 2):zoom(1.75):horizalign(0):maxwidth(420)
		end
	},

	LoadFont("Common Normal")..{
		Name="SongText",
		InitCommand=function(self)
			self:xy(_screen.cx + 70, _screen.cy + 34):zoom(1.9):horizalign(0):vertalign(top):maxwidth(400)
		end
	},

	LoadFont("Common Normal")..{
		Name="ArtistText",
		InitCommand=function(self)
			self:xy(_screen.cx + 70, _screen.cy + 132):zoom(1.35):horizalign(0):maxwidth(500):diffuse(color("#cccccc"))
		end
	},

	LoadFont("Common Normal")..{
		Name="ErrorText",
		InitCommand=function(self)
			self:xy(_screen.cx, _screen.cy + 108):zoom(0.65):maxwidth(900):diffuse(color("#ff6666"))
		end
	},

	Def.ActorFrame{
		Name="ExitConfirm",
		InitCommand=function(self)
			self:visible(false):draworder(9999)
		end,

		Def.Quad{
			InitCommand=function(self)
				self:Center():zoomto(340, 110):diffuse(color("#000000")):diffusealpha(0.85)
			end
		},

		LoadFont("Common Bold")..{
			Text="Exit Queue Mode?",
			InitCommand=function(self)
				self:xy(_screen.cx, _screen.cy - 16):zoom(0.7)
			end
		},

		LoadFont("Common Normal")..{
			Name="ChoiceText",
			InitCommand=function(self)
				self:xy(_screen.cx, _screen.cy + 10):zoom(0.8):diffuse(GetCurrentColor())
			end
		},

		LoadFont("Common Normal")..{
			Text="LEFT/RIGHT choose  START confirm  BACK cancel",
			InitCommand=function(self)
				self:xy(_screen.cx, _screen.cy + 34):zoom(0.6):diffuse(color("#bbbbbb"))
			end
		},
	},

	-- Reuse SelectMusic's existing widgets so Queue mode shows the same
	-- difficulty picker and chart stats UI.
	LoadActor(THEME:GetPathB("ScreenSelectMusic", "overlay/PaneDisplay.lua")),
	LoadActor(THEME:GetPathB("ScreenSelectMusic", "overlay/PerPlayer/default.lua")),
	LoadActor(THEME:GetPathB("ScreenSelectMusic", "overlay/StepsDisplayList/default.lua")),
}

t[#t+1] = LoadActor( THEME:GetPathS("ScreenSelectMaster", "change") )..{ Name="change_sound", IsAction=true, SupportPan=false }
t[#t+1] = LoadActor( THEME:GetPathS("common", "start") )..{ Name="start_sound", IsAction=true, SupportPan=false }

return t
