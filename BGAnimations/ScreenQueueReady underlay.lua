local QUEUE_ENDPOINT = "/api/game/song/current"

local top_screen
local target_song
local available_steps = {}
local selected_index = 1
local queue_state = "loading"
local queue_timeout_seconds = 10
local queue_request_started_at = -1
local queue_consecutive_failures = 0
local queue_failure_threshold = 3
local queue_poll_interval_seconds = 5
local queue_next_poll_at = -1
local queued_song_path = ""
local queued_difficulty_name = ""
local queued_player_name = ""
local queue_error_title = ""
local queue_error_detail = ""
local is_loading = true
local last_up_press = 0
local last_down_press = 0
local double_tap_window = 0.33
local input
local queue_request
local apply_selected_chart

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
	return (path or ""):gsub("\\", "/"):gsub("^/*", ""):gsub("/*$", ""):lower()
end

local find_target_song = function(song_dir)
	local songs = SONGMAN:GetAllSongs() or {}
	local target_dir = normalize(song_dir)
	if target_dir == "" then return nil end

	for song in ivalues(songs) do
		local dir = normalize(song:GetSongDir())
		if dir == target_dir then
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

local find_step_index_for_difficulty = function(steps_list, difficulty_name)
	local normalized_name = normalize(difficulty_name)
	if normalized_name == "" then return nil end

	for i, chart in ipairs(steps_list) do
		local display_name = normalize(chart:GetDifficulty())
		local meter_name = normalize(ToEnumShortString(chart:GetDifficulty()))
		if display_name == normalized_name or meter_name == normalized_name then
			return i
		end
	end

	return nil
end

local get_player_name = function(player_data)
	if type(player_data) == "string" then
		return player_data:gsub("^%s*(.-)%s*$", "%1")
	end

	if type(player_data) ~= "table" then
		return ""
	end

	return player_data.display_name or player_data.username or player_data.name or ""
end

local set_queue_error = function(title, detail)
	queue_state = "error"
	queue_error_title = title or ""
	queue_error_detail = detail or ""
	is_loading = false
	queue_next_poll_at = -1
end

local clear_queue_error = function()
	queue_error_title = ""
	queue_error_detail = ""
end

local set_queue_loading = function()
	queue_state = "loading"
	is_loading = true
	clear_queue_error()
end

local set_queue_empty = function()
	queue_state = "empty"
	is_loading = false
	clear_queue_error()
end

local set_queue_ready = function()
	queue_state = "ready"
	is_loading = false
	clear_queue_error()
	queue_next_poll_at = -1
end

local queue_has_loaded_song = function()
	return queue_state == "ready"
end

local safe_json_decode = function(body)
	if type(body) ~= "string" or body == "" then
		return nil
	end

	local ok, decoded = pcall(JsonDecode, body)
	if ok then
		return decoded
	end

	return nil
end

local get_response_error_detail = function(response, body)
	if response and response.error and ToEnumShortString(response.error) == "Timeout" then
		return THEME:GetString("ScreenQueueReady", "RequestTimedOut"):format(queue_timeout_seconds)
	end

	if type(body) == "table" then
		if type(body.error) == "string" and body.error ~= "" then
			return body.error
		end
		if type(body.message) == "string" and body.message ~= "" then
			return body.message
		end
	end

	if response and response.statusCode then
		return THEME:GetString("ScreenQueueReady", "RequestStatus"):format(response.statusCode)
	end

	if response and response.error then
		return tostring(response.error)
	end

	return THEME:GetString("ScreenQueueReady", "RequestFailed")
end

local schedule_queue_poll = function()
	queue_next_poll_at = GetTimeSinceStart() + queue_poll_interval_seconds
end

local handle_queue_request_failure = function(frame, detail)
	queue_consecutive_failures = queue_consecutive_failures + 1

	if queue_consecutive_failures >= queue_failure_threshold then
		set_queue_error(
			THEME:GetString("ScreenQueueReady", "ConnectionError"),
			detail
		)
		frame:playcommand("Refresh")
		return
	end

	schedule_queue_poll()

	if queue_state == "empty" then
		-- Stay on the empty-queue message while polling in the background.
	else
		queue_state = "loading"
		is_loading = true
	end

	frame:playcommand("Refresh")
end

local request_queue_song = function(frame, show_loading)
	if not frame then return end

	local config = (SL.Global and SL.Global.StepManiaServer) or {}
	local base_url = config.Url or ""
	local token = config.Token or ""

	target_song = nil
	available_steps = {}
	selected_index = 1
	queued_song_path = ""
	queued_difficulty_name = ""
	queued_player_name = ""

	if show_loading then
		set_queue_loading()
	end

	queue_request_started_at = GetTimeSinceStart()
	queue_next_poll_at = -1

	if queue_request then
		queue_request:Cancel()
		queue_request = nil
	end

	if base_url == "" or token == "" then
		set_queue_error(
			THEME:GetString("ScreenQueueReady", "ConnectionError"),
			THEME:GetString("ScreenQueueReady", "MissingConfig")
		)
		frame:playcommand("Refresh")
		return
	end

	frame:playcommand("Refresh")

	queue_request = NETWORK:HttpRequest{
		url=base_url .. QUEUE_ENDPOINT,
		method="GET",
		headers={
			Authorization="Bearer " .. token,
		},
		connectTimeout=queue_timeout_seconds,
		transferTimeout=queue_timeout_seconds,
		onResponse=function(response)
			queue_request = nil
			local body = safe_json_decode(response and response.body or "")

			if not response or response.statusCode ~= 200 then
				handle_queue_request_failure(frame, get_response_error_detail(response, body))
				return
			end

			if type(body) ~= "table" then
				handle_queue_request_failure(frame, THEME:GetString("ScreenQueueReady", "InvalidResponse"))
				return
			end

			queue_consecutive_failures = 0
			if type(body.song) ~= "table" or type(body.song.file_path) ~= "string" or body.song.file_path == "" then
				set_queue_empty()
				schedule_queue_poll()
				frame:playcommand("Refresh")
				return
			end

			queued_song_path = body.song.file_path or ""
			queued_difficulty_name = body.song.difficulty_name or ""
			queued_player_name = get_player_name(body.player)

			target_song = find_target_song(queued_song_path)
			if not target_song then
				handle_queue_request_failure(frame, THEME:GetString("ScreenQueueReady", "MissingSong"):format(queued_song_path))
				frame:playcommand("Refresh")
				return
			end

			available_steps = get_steps_for_current_style(target_song)
			if #available_steps == 0 then
				handle_queue_request_failure(frame, THEME:GetString("ScreenQueueReady", "MissingChart"))
				frame:playcommand("Refresh")
				return
			end

			set_queue_ready()
			selected_index = find_step_index_for_difficulty(available_steps, queued_difficulty_name) or 1
			apply_selected_chart()
			frame:playcommand("Refresh")
		end,
	}
end

apply_selected_chart = function()
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
	local loaded_content = frame:GetChild("LoadedContent")
	local state_overlay = frame:GetChild("StateOverlay")
	local state_title = state_overlay and state_overlay:GetChild("StateTitle")
	local state_detail = state_overlay and state_overlay:GetChild("StateDetail")
	local state_footer = state_overlay and state_overlay:GetChild("StateFooter")

	if loaded_content then
		loaded_content:visible(queue_has_loaded_song())
	end

	if state_overlay then
		state_overlay:visible(not queue_has_loaded_song())
	end

	if is_loading then
		if state_title then state_title:settext(THEME:GetString("ScreenQueueReady", "LoadingTitle")) end
		if state_detail then state_detail:settext(THEME:GetString("ScreenQueueReady", "LoadingPrompt")) end
		if state_footer then state_footer:settext(THEME:GetString("ScreenQueueReady", "LoadingFooter")) end
		return
	end

	if queue_state == "empty" then
		if state_title then state_title:settext(THEME:GetString("ScreenQueueReady", "EmptyTitle")) end
		if state_detail then state_detail:settext(THEME:GetString("ScreenQueueReady", "EmptyDetail")) end
		if state_footer then state_footer:settext(THEME:GetString("ScreenQueueReady", "EmptyFooter")) end
		return
	end

	if queue_error_title ~= "" then
		if state_title then state_title:settext(queue_error_title) end
		if state_detail then state_detail:settext(queue_error_detail) end
		if state_footer then state_footer:settext(THEME:GetString("ScreenQueueReady", "ErrorFooter")) end
		return
	end

	local user_text = loaded_content and loaded_content:GetChild("UsernameText")
	local song_text = loaded_content and loaded_content:GetChild("SongText")
	local artist_text = loaded_content and loaded_content:GetChild("ArtistText")
	local error_text = loaded_content and loaded_content:GetChild("ErrorText")
	local prompt_text = loaded_content and loaded_content:GetChild("PromptText")

	local subtitle = target_song:GetDisplaySubTitle() or ""
	local title = target_song:GetDisplayMainTitle() or ""
	if subtitle ~= "" then
		title = title .. "\n" .. subtitle
	end

	error_text:settext("")
	user_text:settext(queued_player_name ~= "" and queued_player_name or THEME:GetString("ScreenQueueReady", "NoPlayer"))
	song_text:settext(title)
	artist_text:settext(target_song:GetDisplayArtist() or "")

	if prompt_text then
		prompt_text:zoom(0.75):settext(THEME:GetString("ScreenQueueReady", "ReadyPrompt"))
	end
end

input = function(event)
	if not event or event.type == "InputEventType_Release" then return false end

	if event.GameButton == "MenuUp" then
		if is_loading or queue_error_title ~= "" then return true end
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
		if is_loading or queue_error_title ~= "" then return true end
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
		if is_loading then
			return true
		end

		if queue_state == "empty" then
			return true
		end

		if queue_error_title ~= "" then
			local underlay = top_screen and top_screen:GetChild("Underlay")
			if underlay then
				local snd = underlay:GetChild("change_sound")
				if snd then snd:play() end
				request_queue_song(underlay, true)
			else
				SCREENMAN:SystemMessage(THEME:GetString("ScreenQueueReady", "RequestFailed"))
			end
			return true
		end

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
			-- Server mode reuses ITG preferences/metrics while preserving its own mode key.
			SL.Global.ServerModeActive = true
			SL.Global.GameMode = "Server"
			transition_to("ScreenGameplay")
		else
			SCREENMAN:SystemMessage("Server mode could not start (missing player or chart).")
		end
		return true
	end

	if is_back_button(event) then
		local snd = top_screen:GetChild("Underlay") and top_screen:GetChild("Underlay"):GetChild("change_sound")
		if snd then snd:play() end
		SL.Global.ServerModeActive = false
		transition_to("ScreenTitleMenu")
		return true
	end

	return false
end

local t = Def.ActorFrame{
	OnCommand=function(self)
		top_screen = SCREENMAN:GetTopScreen()
		SL.Global.ServerModeActive = true
		self:SetUpdateFunction(function(actor)
			local now = GetTimeSinceStart()

			if queue_request and (now - queue_request_started_at) >= queue_timeout_seconds then
				queue_request:Cancel()
				queue_request = nil
				handle_queue_request_failure(
					actor,
					THEME:GetString("ScreenQueueReady", "RequestTimedOut"):format(queue_timeout_seconds)
				)
				return
			end

			if not queue_request and queue_next_poll_at > 0 and now >= queue_next_poll_at then
				request_queue_song(actor, false)
			end
		end)
		-- Keep Server mode in a valid playmode for gameplay startup.
		GAMESTATE:SetCurrentPlayMode("PlayMode_Regular")
		local song_options = GAMESTATE:GetSongOptionsObject("ModsLevel_Preferred")
		if song_options then
			song_options:MusicRate(SL.Global.ActiveModifiers.MusicRate)
		end

		if GAMESTATE:GetNumSidesJoined() == 0 then
			GAMESTATE:JoinPlayer(PLAYER_1)
		end

		selected_index = 1
		last_up_press = 0
		last_down_press = 0

		self:playcommand("Refresh")

		if top_screen then
			top_screen:AddInputCallback(input)
		end

		request_queue_song(self, true)
	end,

	OffCommand=function(self)
		if queue_request then
			queue_request:Cancel()
			queue_request = nil
		end
		self:SetUpdateFunction(nil)
		queue_next_poll_at = -1
		if top_screen then
			top_screen:RemoveInputCallback(input)
		end
	end,

	RefreshCommand=function(self)
		update_view(self)
	end,

	Def.ActorFrame{
		Name="LoadedContent",
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

		-- Reuse SelectMusic's existing widgets so Server mode shows the same
		-- difficulty picker and chart stats UI.
		LoadActor(THEME:GetPathB("ScreenSelectMusic", "overlay/PaneDisplay.lua")),
		LoadActor(THEME:GetPathB("ScreenSelectMusic", "overlay/PerPlayer/default.lua")),
		LoadActor(THEME:GetPathB("ScreenSelectMusic", "overlay/StepsDisplayList/default.lua")),
	},

	Def.ActorFrame{
		Name="StateOverlay",
		InitCommand=function(self)
			self:visible(false)
		end,

		Def.Quad{
			InitCommand=function(self)
				self:Center():zoomto(720, 220):diffuse(color("#000000")):diffusealpha(0.78)
			end
		},

		LoadFont("Common Bold")..{
			Name="StateTitle",
			InitCommand=function(self)
				self:xy(_screen.cx, _screen.cy - 44):zoom(0.85):maxwidth(700)
			end
		},

		LoadFont("Common Normal")..{
			Name="StateDetail",
			InitCommand=function(self)
				self:xy(_screen.cx, _screen.cy + 2):zoom(0.72):maxwidth(860):wrapwidthpixels(840)
			end
		},

		LoadFont("Common Normal")..{
			Name="StateFooter",
			InitCommand=function(self)
				self:xy(_screen.cx, _screen.cy + 72):zoom(0.62):maxwidth(900):diffuse(color("#bbbbbb"))
			end
		},
	},
}

t[#t+1] = LoadActor( THEME:GetPathS("ScreenSelectMaster", "change") )..{ Name="change_sound", IsAction=true, SupportPan=false }
t[#t+1] = LoadActor( THEME:GetPathS("common", "start") )..{ Name="start_sound", IsAction=true, SupportPan=false }

return t
