local CURRENT_ENDPOINT = "/api/game/song/current"
local SKIP_ENDPOINT = "/api/game/song/skip"
local FINISH_ENDPOINT = "/api/game/song/finish"

local top_screen
local overlay_actor
local finish_request
local skip_request
local poll_request
local finish_request_started_at = -1
local poll_request_started_at = -1
local timeout_seconds = 10
local poll_interval_seconds = 5
local next_poll_at = -1

local master_player = GAMESTATE:GetMasterPlayerNumber()
local player_stats = STATSMAN:GetCurStageStats():GetPlayerStageStats(master_player)
local current_steps = GAMESTATE:GetCurrentSteps(master_player)
local current_score = GetStepManiaServerScoreFromPercentDP(player_stats:GetPercentDancePoints())
local current_grade = GetStepManiaServerGradeString(player_stats:GetGrade())
local current_difficulty_name = GetStepManiaServerDifficultyNameForSteps(current_steps)
local failed = STATSMAN:GetCurStageStats():AllFailed()

local finish_status = failed and "viewing" or "submitting"
local finish_detail = ""
local menu_index = 1
local pre_play = SL.Global.ServerQueueStartBaseline or {}
local post_play = SL.Global.ServerQueueFinishResult or nil
local next_queue_label = ""
local input
local input_ready_at = -1

local clear_server_session_state = function()
	SL.Global.ServerModeActive = false
	SL.Global.ServerQueueItemId = nil
	SL.Global.ServerQueueSelectedDifficultyName = ""
	SL.Global.ServerQueueCurrent = nil
	SL.Global.ServerQueuePrefetch = nil
	SL.Global.ServerQueueStartBaseline = nil
	SL.Global.ServerQueueFinishResult = nil
end

local get_player_name = function(player_data)
	if type(player_data) == "string" then
		return player_data:gsub("^%s*(.-)%s*$", "%1")
	end
	if type(player_data) ~= "table" then return "" end
	return player_data.display_name or player_data.username or player_data.name or ""
end

local normalize = function(text)
	return tostring(text or ""):gsub("^%s*(.-)%s*$", "%1"):lower()
end

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

local safe_json_decode = function(body)
	if type(body) ~= "string" or body == "" then return nil end
	local ok, decoded = pcall(JsonDecode, body)
	return ok and decoded or nil
end

local build_server_request = function(endpoint, method, body, on_response)
	local config = (SL.Global and SL.Global.StepManiaServer) or {}
	local base_url = config.Url or ""
	local token = config.Token or ""
	if base_url == "" or token == "" then
		return nil, THEME:GetString("ScreenQueueReady", "MissingConfig")
	end
	local headers = { Authorization = "Bearer " .. token }
	local request_body = nil
	if body ~= nil then
		request_body = JsonEncode(body)
		headers["Content-Type"] = "application/json"
	end
	return NETWORK:HttpRequest{
		url = base_url .. endpoint,
		method = method,
		headers = headers,
		body = request_body,
		connectTimeout = timeout_seconds,
		transferTimeout = timeout_seconds,
		onResponse = on_response,
	}, nil
end

local get_error_detail = function(response, body)
	if response and response.error and ToEnumShortString(response.error) == "Timeout" then
		return THEME:GetString("ScreenQueueReady", "RequestTimedOut"):format(timeout_seconds)
	end
	if type(body) == "table" and type(body.error) == "string" and body.error ~= "" then
		return body.error
	end
	if response and response.statusCode then
		return THEME:GetString("ScreenQueueReady", "RequestStatus"):format(response.statusCode)
	end
	return THEME:GetString("ScreenQueueReady", "RequestFailed")
end

local format_high_score = function(score_data)
	if type(score_data) ~= "table" then
		return THEME:GetString("ScreenQueueReady", "NoHighScore")
	end
	local score = tonumber(score_data.score)
	local grade = tostring(score_data.grade or "")
	local parts = {}
	if score then parts[#parts+1] = ("%0.2f%%"):format(score) end
	if grade ~= "" then parts[#parts+1] = grade end
	return #parts > 0 and table.concat(parts, "  ") or THEME:GetString("ScreenQueueReady", "NoHighScore")
end

local format_machine_holder = function(score_data)
	if type(score_data) ~= "table" or type(score_data.held_by) ~= "string" or score_data.held_by == "" then
		return ""
	end
	return THEME:GetString("ScreenQueueReady", "MachineHolder"):format(score_data.held_by)
end

local did_beat_baseline = function(baseline, new_score)
	local baseline_score = baseline and tonumber(baseline.score) or nil
	local score_value = tonumber(new_score)
	if not score_value then return false end
	if baseline_score == nil then return true end
	return score_value > baseline_score
end

local update_next_queue_label = function(body)
	if type(body) ~= "table" or type(body.song) ~= "table" or type(body.song.file_path) ~= "string" or body.song.file_path == "" then
		next_queue_label = THEME:GetString("ScreenEvaluation", "ServerQueueEmpty")
		return
	end
	local difficulty_name = tostring(body.song.difficulty_name or "")
	local player_name = get_player_name(body.player)
	local detail = body.song.file_path
	if difficulty_name ~= "" then detail = ("%s  •  %s"):format(detail, difficulty_name) end
	if player_name ~= "" then detail = ("%s  •  %s"):format(detail, player_name) end
	next_queue_label = detail
end

local start_polling = function()
	next_poll_at = GetTimeSinceStart() + poll_interval_seconds
end

local restore_engine_input = function()
	for player in ivalues(GAMESTATE:GetHumanPlayers()) do
		SCREENMAN:set_input_redirected(player, false)
	end
end

local transition_to_queue_ready = function()
	if not top_screen then return end
	restore_engine_input()
	SL.Global.GameMode = "Server"
	top_screen:SetNextScreenName("ScreenQueueReady")
	top_screen:StartTransitioningScreen("SM_GoToNextScreen")
end

local request_current = function()
	if poll_request then poll_request:Cancel(); poll_request = nil end
	local request, _ = build_server_request(CURRENT_ENDPOINT, "GET", nil, function(response)
		poll_request = nil
		local body = safe_json_decode(response and response.body or "")
		if not response or response.statusCode ~= 200 or type(body) ~= "table" then
			start_polling()
			return
		end
		SL.Global.ServerQueuePrefetch = body
		update_next_queue_label(body)
		if overlay_actor then overlay_actor:queuecommand("RefreshServerQueueFlow") end
		start_polling()
	end)
	if request then
		poll_request = request
		poll_request_started_at = GetTimeSinceStart()
	end
end

local request_finish = function()
	finish_status = "submitting"
	finish_detail = THEME:GetString("ScreenEvaluation", "ServerSubmitting")
	if overlay_actor then overlay_actor:queuecommand("RefreshServerQueueFlow") end

	if finish_request then finish_request:Cancel(); finish_request = nil end

	local body = BuildStepManiaServerSongRequestBody({
		difficulty_name = current_difficulty_name,
		score = current_score,
		grade = current_grade,
	})

	local request, _ = build_server_request(FINISH_ENDPOINT, "POST", body, function(response)
		finish_request = nil
		local decoded = safe_json_decode(response and response.body or "")
		if response and response.statusCode == 200 and type(decoded) == "table" then
			SL.Global.ServerQueueFinishResult = decoded
		end
		transition_to_queue_ready()
	end)

	if request then
		finish_request = request
		finish_request_started_at = GetTimeSinceStart()
	else
		transition_to_queue_ready()
	end
end

local request_forfeit = function()
	finish_status = "submitting"
	finish_detail = THEME:GetString("ScreenEvaluation", "ServerForfeiting")
	if overlay_actor then overlay_actor:queuecommand("RefreshServerQueueFlow") end

	if skip_request then skip_request:Cancel(); skip_request = nil end

	local body = BuildStepManiaServerSongRequestBody({})

	local request, error_detail = build_server_request(SKIP_ENDPOINT, "POST", body, function(response)
		skip_request = nil
		local decoded = safe_json_decode(response and response.body or "")

		-- treat queue-mismatch as success — queue already moved on
		local ok = (response and response.statusCode == 200)
			or (type(decoded) == "table" and (
				normalize(tostring(decoded.error or "")) == normalize("queue_item_id does not match the current queue item")
				or normalize(tostring(decoded.error or "")) == normalize("No current song set")
			))

		if ok then
			clear_server_session_state()
			restore_engine_input()
			if top_screen then
				top_screen:SetNextScreenName("ScreenQueueReady")
				top_screen:StartTransitioningScreen("SM_GoToNextScreen")
			end
			return
		end

		-- forfeit failed — fall back to showing error then allowing retry/continue
		finish_status = "menu"
		finish_detail = get_error_detail(response, decoded)
		if overlay_actor then overlay_actor:queuecommand("RefreshServerQueueFlow") end
	end)

	if request then
		skip_request = request
	else
		-- no config / request build failed — just clear and exit
		clear_server_session_state()
		restore_engine_input()
		if top_screen then
			top_screen:SetNextScreenName("ScreenTitleMenu")
			top_screen:StartTransitioningScreen("SM_GoToNextScreen")
		end
	end
end

input = function(event)
	if not event then return false end

	if event.type == "InputEventType_Release" then
		return false
	end

	if event.type ~= "InputEventType_FirstPress" then
		return true  -- consume repeat events without processing
	end

	if GetTimeSinceStart() < input_ready_at then
		return true
	end

	if finish_status == "viewing" then
		finish_status = "menu"
		if overlay_actor then overlay_actor:queuecommand("RefreshServerQueueFlow") end
		return true
	end

	if finish_status == "menu" then
		if event.GameButton == "MenuUp" or event.GameButton == "MenuLeft" then
			menu_index = ((menu_index - 2) % 2) + 1
			if overlay_actor then overlay_actor:queuecommand("RefreshServerQueueFlow") end
			return true
		end

		if event.GameButton == "MenuDown" or event.GameButton == "MenuRight" then
			menu_index = (menu_index % 2) + 1
			if overlay_actor then overlay_actor:queuecommand("RefreshServerQueueFlow") end
			return true
		end

		if is_back_button(event) then
			return true
		end

		if is_start_button(event) then
			if menu_index == 1 then
				request_forfeit()
			else
				transition_to_queue_ready()
			end
			return true
		end

		return true
	end

	if finish_status == "submitting" then
		if is_start_button(event) then
			if finish_request then finish_request:Cancel(); finish_request = nil end
			transition_to_queue_ready()
		end
		return true
	end

	return false
end

local menu_num_options = 2

local af = Def.ActorFrame{
	Name="ServerQueueFlow",
	OnCommand=function(self)
		overlay_actor = self
		top_screen = SCREENMAN:GetTopScreen()
		input_ready_at = GetTimeSinceStart() + 0.6
		if top_screen then
			top_screen:AddInputCallback(input)
			if top_screen.lockinput then
				top_screen:lockinput(0.6)
			end
		end
		-- disable C++ engine input so our Lua callback has full control
		for player in ivalues(GAMESTATE:GetHumanPlayers()) do
			SCREENMAN:set_input_redirected(player, true)
		end

		self:SetUpdateFunction(function(actor)
			local now = GetTimeSinceStart()

			if finish_request and (now - finish_request_started_at) >= timeout_seconds then
				finish_request:Cancel()
				finish_request = nil
				transition_to_queue_ready()
			end
		end)

		if failed then
			finish_detail = THEME:GetString("ScreenEvaluation", "ServerFailMenuDetail")
		else
			request_finish()
		end

		self:playcommand("RefreshServerQueueFlow")
	end,

	OffCommand=function(self)
		overlay_actor = nil
		if finish_request then finish_request:Cancel() end
		if skip_request then skip_request:Cancel() end
		if poll_request then poll_request:Cancel() end
		self:SetUpdateFunction(nil)
		if top_screen then
			top_screen:RemoveInputCallback(input)
		end
		restore_engine_input()
	end,

	RefreshServerQueueFlowCommand=function(self)
		local results_panel = self:GetChild("ResultsPanel")
		local fail_menu = self:GetChild("FailMenu")

		local show_menu = (finish_status == "menu")
		if fail_menu then fail_menu:visible(show_menu) end
		if results_panel then results_panel:visible(false) end

		-- fail menu option highlighting
		if show_menu and fail_menu then
			for i = 1, menu_num_options do
				local option = fail_menu:GetChild("Option" .. i)
				if option then
					option:diffuse(i == menu_index and color("#ffffff") or color("#bbbbbb"))
				end
			end
		end
	end,

	-- -----------------------------------------------------------------------
	-- "Press Start" nudge shown only during the viewing state (failure only)
	LoadFont("Common Normal")..{
		Name="ViewingHint",
		InitCommand=function(self)
			self:xy(_screen.cx, _screen.h - 24)
				:zoom(0.44):maxwidth(IsUsingWideScreen() and 980 or 800)
				:diffuse(color("#9ca3af")):diffusealpha(0)
		end,
		OnCommand=function(self)
			if failed then
				self:settext(THEME:GetString("ScreenEvaluation", "ServerViewingHint"))
					:linear(0.4):diffusealpha(1)
			end
		end,
		RefreshServerQueueFlowCommand=function(self)
			self:visible(finish_status == "viewing")
		end,
	},

	-- -----------------------------------------------------------------------
	-- Results panel (shown for submitting and results states)
	Def.ActorFrame{
		Name="ResultsPanel",
		InitCommand=function(self) self:visible(false) end,

		-- background: center at cy+100, height 190
		Def.Quad{
			InitCommand=function(self)
				local w = IsUsingWideScreen() and 560 or 460
				self:xy(_screen.cx, _screen.cy + 100)
					:zoomto(w, 190)
					:diffuse(color("#000000")):diffusealpha(0.72)
			end
		},

		-- status line (submitting / recorded / error)
		LoadFont("Common Normal")..{
			Name="StatusText",
			InitCommand=function(self)
				self:xy(_screen.cx, _screen.cy + 12)
					:zoom(0.48):maxwidth(IsUsingWideScreen() and 980 or 800)
					:diffuse(color("#d8d8d8"))
			end
		},

		-- pre-play section
		LoadFont("Common Normal")..{
			Text=THEME:GetString("ScreenEvaluation", "ServerPrePlayLabel"),
			InitCommand=function(self)
				self:xy(_screen.cx, _screen.cy + 36):zoom(0.44):diffuse(color("#9ca3af"))
			end
		},
		LoadFont("Common Normal")..{
			Name="PreUserValue",
			InitCommand=function(self)
				self:xy(_screen.cx, _screen.cy + 54):zoom(0.52):maxwidth(IsUsingWideScreen() and 900 or 740)
			end
		},
		LoadFont("Common Normal")..{
			Name="PreMachineValue",
			InitCommand=function(self)
				self:xy(_screen.cx, _screen.cy + 70):zoom(0.52):maxwidth(IsUsingWideScreen() and 900 or 740)
			end
		},
		-- pre machine holder shares row with machine value via settext
		LoadFont("Common Normal")..{
			Name="PreMachineHolder",
			InitCommand=function(self)
				self:visible(false)  -- unused; holder info omitted for compactness
			end
		},

		-- post-play section
		LoadFont("Common Normal")..{
			Text=THEME:GetString("ScreenEvaluation", "ServerPostPlayLabel"),
			InitCommand=function(self)
				self:xy(_screen.cx, _screen.cy + 94):zoom(0.44):diffuse(color("#9ca3af"))
			end
		},
		LoadFont("Common Normal")..{
			Name="PostUserValue",
			InitCommand=function(self)
				self:xy(_screen.cx, _screen.cy + 112):zoom(0.52):maxwidth(IsUsingWideScreen() and 900 or 740)
			end
		},
		LoadFont("Common Normal")..{
			Name="PostMachineValue",
			InitCommand=function(self)
				self:xy(_screen.cx, _screen.cy + 128):zoom(0.52):maxwidth(IsUsingWideScreen() and 900 or 740)
			end
		},
		LoadFont("Common Normal")..{
			Name="PostMachineHolder",
			InitCommand=function(self)
				self:visible(false)  -- unused; holder info omitted for compactness
			end
		},

		-- PR message
		LoadFont("Common Normal")..{
			Name="PRText",
			InitCommand=function(self)
				self:xy(_screen.cx, _screen.cy + 150):zoom(0.46):maxwidth(IsUsingWideScreen() and 980 or 800):diffuse(color("#ffef9a"))
			end
		},

		-- next queue label
		LoadFont("Common Normal")..{
			Name="NextQueueText",
			InitCommand=function(self)
				self:xy(_screen.cx, _screen.cy + 168):zoom(0.42):maxwidth(IsUsingWideScreen() and 980 or 800):diffuse(color("#c7d2fe"))
			end
		},

		-- control hint at bottom of panel
		LoadFont("Common Normal")..{
			Name="HintText",
			InitCommand=function(self)
				self:xy(_screen.cx, _screen.cy + 186):zoom(0.38):maxwidth(IsUsingWideScreen() and 980 or 800):diffuse(color("#6b7280"))
			end
		},
	},

	-- -----------------------------------------------------------------------
	-- Fail menu (shown only on failure)
	Def.ActorFrame{
		Name="FailMenu",
		InitCommand=function(self) self:visible(false) end,

		Def.Quad{
			InitCommand=function(self)
				local w = IsUsingWideScreen() and 420 or 340
				self:xy(_screen.cx, _screen.cy + 4)
					:zoomto(w, 150)
					:diffuse(color("#000000")):diffusealpha(0.84)
			end
		},
		LoadFont("Common Bold")..{
			Text=THEME:GetString("ScreenEvaluation", "ServerFailMenuTitle"),
			InitCommand=function(self)
				self:xy(_screen.cx, _screen.cy - 60)
					:zoom(0.72):maxwidth(IsUsingWideScreen() and 700 or 580)
			end
		},
		LoadFont("Common Normal")..{
			Text=THEME:GetString("ScreenEvaluation", "ServerForfeit"),
			Name="Option1",
			InitCommand=function(self)
				self:xy(_screen.cx, _screen.cy - 12)
					:zoom(0.80):maxwidth(IsUsingWideScreen() and 680 or 560)
			end
		},
		LoadFont("Common Normal")..{
			Text=THEME:GetString("ScreenEvaluation", "ServerRetry"),
			Name="Option2",
			InitCommand=function(self)
				self:xy(_screen.cx, _screen.cy + 26)
					:zoom(0.80):maxwidth(IsUsingWideScreen() and 680 or 560)
			end
		},
	},
}

return af
