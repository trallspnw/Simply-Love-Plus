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
local current_chart_id = SL.Global.ServerQueueSelectedChartId
local failed = STATSMAN:GetCurStageStats():AllFailed()

local finish_status = failed and "failed" or "submitting"
local finish_detail = ""
local menu_index = 1
local pre_play = SL.Global.ServerQueueStartBaseline or {}
local post_play = SL.Global.ServerQueueFinishResult or nil
local next_queue_label = ""
local input
local input_ready_at = -1

local banner_width = 418 * 0.7
local panel_w = IsUsingWideScreen() and 250 or 168
local panel_h = IsUsingWideScreen() and 136 or 126
local panel_gap = IsUsingWideScreen() and 16 or 8
local panel_x = _screen.cx + (banner_width * 0.5) + panel_gap + (panel_w * 0.5)
local panel_y = 108
local panel_left = panel_x - (panel_w * 0.5) + 12
local panel_top = panel_y - (panel_h * 0.5)
local panel_text_w = IsUsingWideScreen() and 300 or 220

local clear_server_session_state = function()
	SL.Global.ServerModeActive = false
	SL.Global.ServerQueueItemId = nil
	SL.Global.ServerQueueSelectedChartId = nil
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

local format_score_only = function(score_data)
	if type(score_data) ~= "table" then
		return THEME:GetString("ScreenQueueReady", "NoHighScore")
	end
	local score = tonumber(score_data.score)
	if not score then
		return THEME:GetString("ScreenQueueReady", "NoHighScore")
	end
	return ("%0.2f"):format(score)
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

local redirect_engine_input = function()
	for player in ivalues(GAMESTATE:GetHumanPlayers()) do
		SCREENMAN:set_input_redirected(player, true)
	end
end

local transition_to_queue_ready = function()
	if not top_screen then return end
	restore_engine_input()
	SL.Global.GameMode = "Server"
	top_screen:SetNextScreenName("ScreenQueueReady")
	top_screen:StartTransitioningScreen("SM_GoToNextScreen")
end

local get_eval_common_actor = function()
	if not top_screen then return nil end
	local overlay = top_screen:GetChild("Overlay")
	if not overlay then return nil end
	return overlay:GetChild("ScreenEval Common")
end

local get_eval_panes_actor = function()
	local common = get_eval_common_actor()
	if not common then return nil end
	return common:GetChild("Panes")
end

local activate_fail_menu_input_mode = function()
	local common = get_eval_common_actor()
	if common then
		common:playcommand("DirectInputToEventOverlayHandler")
	end
	redirect_engine_input()
end

local get_side_key_for_event = function(event)
	local controller = tonumber(ToEnumShortString(event and event.controller))
	if controller == 1 or controller == 2 then
		return "P" .. controller
	end
	local pn = event and event.PlayerNumber
	if pn == PLAYER_2 then return "P2" end
	return "P1"
end

local find_visible_pane_index = function(panes_actor, side_key, max_panes)
	for i = 1, max_panes do
		local pane = panes_actor:GetChild(("Pane%d_Side%s"):format(i, side_key))
		if pane and pane:GetVisible() then
			return i
		end
	end
	return nil
end

local switch_eval_pane = function(event, delta)
	local panes_actor = get_eval_panes_actor()
	if not panes_actor then return false end

	local side_key = get_side_key_for_event(event)
	local max_panes = 0
	for i = 1, 12 do
		if panes_actor:GetChild(("Pane%d_Side%s"):format(i, side_key)) then
			max_panes = i
		end
	end
	if max_panes <= 1 then return false end

	local active_index = find_visible_pane_index(panes_actor, side_key, max_panes) or 1
	local other_side_key = (side_key == "P1") and "P2" or "P1"
	local other_active_index = find_visible_pane_index(panes_actor, other_side_key, max_panes)

	local next_index = ((active_index - 1 + delta) % max_panes) + 1
	if #GAMESTATE:GetHumanPlayers() == 1 and other_active_index and next_index == other_active_index and max_panes > 1 then
		next_index = ((next_index - 1 + delta) % max_panes) + 1
	end

	for i = 1, max_panes do
		local pane = panes_actor:GetChild(("Pane%d_Side%s"):format(i, side_key))
		if pane then pane:visible(i == next_index) end
	end

	return true
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
		chart_id = current_chart_id,
		score = current_score,
		grade = current_grade,
	})

	local request, _ = build_server_request(FINISH_ENDPOINT, "POST", body, function(response)
		finish_request = nil
		local decoded = safe_json_decode(response and response.body or "")
		if response and response.statusCode == 200 and type(decoded) == "table" then
			post_play = decoded
			SL.Global.ServerQueueFinishResult = decoded
			finish_status = "results"
			finish_detail = THEME:GetString("ScreenEvaluation", "ServerRecorded")
			if overlay_actor then overlay_actor:queuecommand("RefreshServerQueueFlow") end
			request_current()
			return
		end

		local error_text = get_error_detail(response, decoded)
		local ignored = normalize(error_text) == normalize("queue_item_id does not match the current queue item")
			or normalize(error_text) == normalize("No current song set")

		finish_status = "results"
		if ignored then
			finish_detail = THEME:GetString("ScreenEvaluation", "ServerFinishIgnored")
		else
			finish_detail = THEME:GetString("ScreenEvaluation", "ServerFinishFailed"):format(error_text)
		end
		if overlay_actor then overlay_actor:queuecommand("RefreshServerQueueFlow") end
		request_current()
	end)

	if request then
		finish_request = request
		finish_request_started_at = GetTimeSinceStart()
	else
		finish_status = "results"
		finish_detail = THEME:GetString("ScreenEvaluation", "ServerFinishFailed"):format(THEME:GetString("ScreenQueueReady", "RequestFailed"))
		if overlay_actor then overlay_actor:queuecommand("RefreshServerQueueFlow") end
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

	if finish_status == "failed" then
		if event.GameButton == "MenuLeft" then
			return switch_eval_pane(event, -1)
		end

		if event.GameButton == "MenuRight" then
			return switch_eval_pane(event, 1)
		end

		if is_start_button(event) then
			finish_status = "menu"
			activate_fail_menu_input_mode()
			if overlay_actor then overlay_actor:queuecommand("RefreshServerQueueFlow") end
			return true
		end

		if is_back_button(event) then
			return true
		end

		return true
	end

	if finish_status == "submitting" then
		return true
	end

	if finish_status == "results" then
		if is_start_button(event) then
			transition_to_queue_ready()
			return true
		end

		if is_back_button(event) then
			clear_server_session_state()
			restore_engine_input()
			if top_screen then
				top_screen:SetNextScreenName("ScreenTitleMenu")
				top_screen:StartTransitioningScreen("SM_GoToNextScreen")
			end
			return true
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
		redirect_engine_input()

		self:SetUpdateFunction(function(actor)
			local now = GetTimeSinceStart()

			if finish_request and (now - finish_request_started_at) >= timeout_seconds then
				finish_request:Cancel()
				finish_request = nil
				finish_status = "results"
				finish_detail = THEME:GetString("ScreenEvaluation", "ServerFinishFailed"):format(
					THEME:GetString("ScreenQueueReady", "RequestTimedOut"):format(timeout_seconds)
				)
				actor:playcommand("RefreshServerQueueFlow")
				request_current()
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
		if results_panel then
			results_panel:visible(not failed and (finish_status == "submitting" or finish_status == "results"))

			local primary = results_panel:GetChild("PrimaryMessage")
			local secondary = results_panel:GetChild("SecondaryMessage")
			local tertiary = results_panel:GetChild("TertiaryMessage")

			local server_pr = did_beat_baseline(pre_play.server_highscore, current_score)
			local personal_pr = did_beat_baseline(pre_play.user_highscore, current_score)
			local latest_user = (post_play and post_play.user_highscore) or pre_play.user_highscore
			local latest_server = (post_play and post_play.server_highscore) or pre_play.server_highscore

			if finish_status == "submitting" then
				primary:settext(THEME:GetString("ScreenEvaluation", "ServerSubmitting"))
				primary:diffuse(color("#d8d8d8")):zoom(0.36)
				secondary:settext("")
				tertiary:settext("")
			elseif server_pr then
				primary:settext("Server Record!")
				primary:diffuse(color("#f5d36a")):zoom(0.62)
				secondary:settext("")
				tertiary:settext("")
			elseif personal_pr then
				primary:settext("Personal Record!")
				primary:diffuse(color("#d8dde6")):zoom(0.44)
				secondary:settext("Machine Record: " .. format_score_only(latest_server))
				secondary:zoom(0.44)
				tertiary:settext("")
			else
				primary:settext("Personal Record: " .. format_score_only(latest_user))
				primary:diffuse(color("#d8d8d8")):zoom(0.34)
				secondary:settext("Machine Record: " .. format_score_only(latest_server))
				secondary:zoom(0.32)
				tertiary:settext("")
			end
		end

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
	-- Results panel (shown for submitting and results states)
	Def.ActorFrame{
		Name="ResultsPanel",
		InitCommand=function(self) self:visible(false) end,

		Def.Quad{
			InitCommand=function(self)
				self:xy(panel_x, panel_y)
					:zoomto(panel_w, panel_h)
					:diffuse(color("#000000")):diffusealpha(0.72)
			end
		},

		LoadFont("Common Bold")..{
			Name="PrimaryMessage",
			InitCommand=function(self)
				self:xy(panel_x, panel_y - 12)
					:zoom(0.56)
					:maxwidth(panel_w * 1.45)
					:vertalign(0.5)
			end
		},
		LoadFont("Common Bold")..{
			Name="SecondaryMessage",
			InitCommand=function(self)
				self:xy(panel_x, panel_y + 18)
					:zoom(0.44)
					:maxwidth(panel_w * 1.7)
					:diffuse(color("#d8d8d8"))
					:vertalign(0.5)
			end
		},
		LoadFont("Common Normal")..{
			Name="TertiaryMessage",
			InitCommand=function(self)
				self:xy(panel_x, panel_y + 40)
					:zoom(0.30)
					:maxwidth(panel_w * 1.7)
					:diffuse(color("#c7d2fe"))
					:vertalign(0.5)
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
				self:xy(_screen.cx, _screen.cy)
					:zoomto(IsUsingWideScreen() and 260 or 220, 120)
					:diffuse(color("#000000")):diffusealpha(0.84)
			end
		},
		LoadFont("Common Normal")..{
			Text=THEME:GetString("ScreenEvaluation", "ServerForfeit"),
			Name="Option1",
			InitCommand=function(self)
				self:xy(_screen.cx, _screen.cy - 18)
					:zoom(1.16)
					:maxwidth(320)
			end
		},
		LoadFont("Common Normal")..{
			Text=THEME:GetString("ScreenEvaluation", "ServerRetry"),
			Name="Option2",
			InitCommand=function(self)
				self:xy(_screen.cx, _screen.cy + 20)
					:zoom(1.16)
					:maxwidth(320)
			end
		},
	},
}

return af
