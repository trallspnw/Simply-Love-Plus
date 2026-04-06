local CURRENT_ENDPOINT = "/api/game/song/current"
local START_ENDPOINT = "/api/game/song/start"
local SKIP_ENDPOINT = "/api/game/song/skip"

local banner_width = 418
local banner_height = 164
local queue_timeout_seconds = 10
local queue_poll_interval_seconds = 5
local queue_failure_threshold = 3
local queue_preview_start_delay_seconds = 0.35

local top_screen
local current_request
local current_request_started_at = -1
local queue_next_poll_at = -1
local queue_consecutive_failures = 0

local queue_state = "loading"
local queue_error_title = ""
local queue_error_detail = ""
local target_song
local available_chart_options = {}
local selected_index = 1
local preview_song_dir = ""
local next_preview_attempt_at = -1
local preview_retry_interval_seconds = 0.35
local current_queue_item_id = nil
local current_chart_id = nil
local queued_song_path = ""
local queued_difficulty_name = ""
local queued_player_name = ""
local queued_user_highscore = nil
local queued_server_highscore = nil
local queued_chart_highscores = nil

local modal_mode = nil
local modal_title = ""
local modal_detail = ""
local modal_options = {}
local modal_index = 1
local pending_action = nil
local input
local last_diff_direction = nil
local last_diff_press_at = -1
local diff_double_press_window = 0.45
local play_song_preview
local stop_song_preview

local normalize = function(text)
	return tostring(text or ""):gsub("\\", "/"):gsub("^%s*(.-)%s*$", "%1"):gsub("^/*", ""):gsub("/*$", ""):lower()
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

local strip_group_variant = function(path)
	local normalized = normalize(path)
	local prefix = ""

	if normalized:sub(1, 6) == "songs/" then
		prefix = "songs/"
		normalized = normalized:sub(#prefix + 1)
	end

	local slash = normalized:find("/", 1, true)
	local group = slash and normalized:sub(1, slash - 1) or normalized
	local rest = slash and normalized:sub(slash + 1) or ""

	group = group:gsub("%s+%b[]$", "")

	if rest ~= "" then
		return prefix .. group .. "/" .. rest
	end

	return prefix .. group
end

local find_target_song = function(song_dir)
	local songs = SONGMAN:GetAllSongs() or {}
	local target_dir = normalize(song_dir)
	if target_dir == "" then return nil end

	local candidate_dirs = {
		[target_dir] = true,
		[strip_group_variant(target_dir)] = true,
	}

	if target_dir:sub(1, 6) == "songs/" then
		candidate_dirs[target_dir:gsub("^songs/", "", 1)] = true
		candidate_dirs[strip_group_variant(target_dir:gsub("^songs/", "", 1))] = true
	else
		candidate_dirs["songs/" .. target_dir] = true
		candidate_dirs[strip_group_variant("songs/" .. target_dir)] = true
	end

	for song in ivalues(songs) do
		local dir = normalize(song:GetSongDir())
		if candidate_dirs[dir] or candidate_dirs[strip_group_variant(dir)] then
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
	for i, chart in ipairs(steps_list) do
		if DoesStepManiaServerDifficultyMatch(chart, difficulty_name) then
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

local safe_json_decode = function(body)
	if type(body) ~= "string" or body == "" then
		return nil
	end

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

	local headers = {
		Authorization="Bearer " .. token,
	}

	local request_body = nil
	if body ~= nil then
		request_body = JsonEncode(body)
		headers["Content-Type"] = "application/json"
	end

	return NETWORK:HttpRequest{
		url=base_url .. endpoint,
		method=method,
		headers=headers,
		body=request_body,
		connectTimeout=queue_timeout_seconds,
		transferTimeout=queue_timeout_seconds,
		onResponse=on_response,
	}, nil
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

	return THEME:GetString("ScreenQueueReady", "RequestFailed")
end

local clear_queue_context = function()
	if SOUND and SOUND.StopMusic then
		pcall(function() SOUND:StopMusic() end)
	end
	target_song = nil
	available_chart_options = {}
	selected_index = 1
	preview_song_dir = ""
	next_preview_attempt_at = -1
	current_queue_item_id = nil
	current_chart_id = nil
	queued_song_path = ""
	queued_difficulty_name = ""
	queued_player_name = ""
	queued_user_highscore = nil
	queued_server_highscore = nil
	queued_chart_highscores = nil
	SL.Global.ServerQueueItemId = nil
	SL.Global.ServerQueueSelectedChartId = nil
	SL.Global.ServerQueueCurrent = nil
	SL.Global.ServerQueueSelectedDifficultyName = ""
end

local clear_server_session_state = function()
	clear_queue_context()
	SL.Global.ServerQueueCurrent = nil
	SL.Global.ServerQueuePrefetch = nil
	SL.Global.ServerQueueStartBaseline = nil
	SL.Global.ServerQueueFinishResult = nil
end

local set_queue_error = function(title, detail)
	queue_state = "error"
	queue_error_title = title or ""
	queue_error_detail = detail or ""
	queue_next_poll_at = -1
	stop_song_preview()
end

local set_queue_loading = function()
	queue_state = "loading"
	queue_error_title = ""
	queue_error_detail = ""
	stop_song_preview()
end

local set_queue_empty = function()
	queue_state = "empty"
	queue_error_title = ""
	queue_error_detail = ""
	stop_song_preview()
end

local set_queue_ready = function()
	queue_state = "ready"
	queue_error_title = ""
	queue_error_detail = ""
	next_preview_attempt_at = GetTimeSinceStart() + queue_preview_start_delay_seconds
end

local queue_has_loaded_song = function()
	return queue_state == "ready"
end

local schedule_queue_poll = function()
	queue_next_poll_at = GetTimeSinceStart() + queue_poll_interval_seconds
end

local get_selected_chart_option = function()
	return available_chart_options[selected_index]
end

local get_selected_steps = function()
	local option = get_selected_chart_option()
	return option and option.steps or nil
end

local get_selected_difficulty_name = function()
	local option = get_selected_chart_option()
	if option and option.difficulty_name and option.difficulty_name ~= "" then
		return option.difficulty_name
	end
	return GetStepManiaServerDifficultyNameForSteps(get_selected_steps())
end

local get_selected_chart_id = function()
	local option = get_selected_chart_option()
	return option and option.chart_id or nil
end

local apply_selected_chart = function()
	if not target_song then return end

	local steps = get_selected_steps()
	if not steps then return end

	GAMESTATE:SetCurrentSong(target_song)
	for pn in ivalues(GAMESTATE:GetHumanPlayers()) do
		GAMESTATE:SetCurrentSteps(pn, steps)
		GAMESTATE:SetPreferredDifficulty(pn, steps:GetDifficulty())
	end

	current_chart_id = get_selected_chart_id()
	SL.Global.ServerQueueSelectedChartId = current_chart_id
	SL.Global.ServerQueueSelectedDifficultyName = get_selected_difficulty_name()
end

local get_song_preview_metadata = function(song)
	if not song then return nil end

	local music_path = nil
	local start_seconds = 0
	local length_seconds = 15

	pcall(function() music_path = song:GetMusicPath() end)
	pcall(function() start_seconds = song:GetSampleStart() or start_seconds end)
	pcall(function() length_seconds = song:GetSampleLength() or length_seconds end)

	if not music_path or music_path == "" then
		return nil
	end

	if tonumber(length_seconds) == nil or length_seconds <= 0 then
		length_seconds = 15
	end

	return {
		path = music_path,
		start = tonumber(start_seconds) or 0,
		length = tonumber(length_seconds) or 15,
	}
end

play_song_preview = function(song)
	if not song then return end
	local song_dir = normalize(song:GetSongDir())
	if song_dir ~= "" and song_dir == preview_song_dir then
		return
	end

	local preview = get_song_preview_metadata(song)
	if not preview or not SOUND then
		return
	end

	local ok = pcall(function()
		if SOUND.PlayMusicPart then
			SOUND:PlayMusicPart(preview.path, preview.start, preview.length, 0.15, 1.0, true)
		elseif SOUND.PlayMusicPartOnce then
			SOUND:PlayMusicPartOnce(preview.path, preview.start, preview.length, 0.15, 1.0)
		elseif SOUND.PlayMusic then
			SOUND:PlayMusic(preview.path)
		end
	end)

	if ok then
		preview_song_dir = song_dir
		next_preview_attempt_at = -1
	end
end

stop_song_preview = function()
	preview_song_dir = ""
	next_preview_attempt_at = -1
	if SOUND and SOUND.StopMusic then
		pcall(function() SOUND:StopMusic() end)
	end
end

local queue_context_from_body = function(body)
	if type(body) ~= "table" then return nil end
	if type(body.song) ~= "table" or type(body.song.file_path) ~= "string" or body.song.file_path == "" then
		return {
			queue_item_id = nil,
			song = nil,
			player_name = "",
			user_highscore = nil,
			server_highscore = nil,
		}
	end

	return {
		queue_item_id = tonumber(body.queue_item_id),
		song = body.song,
		player_name = get_player_name(body.player),
		user_highscore = body.user_highscore,
		server_highscore = body.server_highscore,
	}
end

local close_modal = function()
	modal_mode = nil
	modal_title = ""
	modal_detail = ""
	modal_options = {}
	modal_index = 1
	pending_action = nil
end

local open_busy_modal = function(title, detail, action_name)
	modal_mode = "busy"
	modal_title = title or ""
	modal_detail = detail or ""
	modal_options = {}
	modal_index = 1
	pending_action = action_name
end

local open_back_menu = function()
	modal_mode = "menu"
	modal_title = THEME:GetString("ScreenQueueReady", "BackMenuTitle")
	modal_detail = THEME:GetString("ScreenQueueReady", "BackMenuDetail")
	modal_options = {
		THEME:GetString("ScreenQueueReady", "MenuContinue"),
		THEME:GetString("ScreenQueueReady", "MenuSongOptions"),
		THEME:GetString("ScreenQueueReady", "MenuSkip"),
		THEME:GetString("ScreenQueueReady", "MenuExit"),
	}
	modal_index = 1
	pending_action = nil
end

local format_high_score = function(score_data)
	if type(score_data) ~= "table" then
		return THEME:GetString("ScreenQueueReady", "NoHighScore")
	end

	local score = tonumber(score_data.score)
	if not score then
		return THEME:GetString("ScreenQueueReady", "NoHighScore")
	end

	return ("%0.2f"):format(score)
end

local format_machine_holder = function(score_data)
	if type(score_data) ~= "table" or type(score_data.held_by) ~= "string" or score_data.held_by == "" then
		return ""
	end

	return THEME:GetString("ScreenQueueReady", "MachineHolder"):format(score_data.held_by)
end

local update_highscores_for_selected_difficulty = function()
	local option = get_selected_chart_option()
	if option then
		queued_user_highscore = option.user_highscore
		queued_server_highscore = option.server_highscore
	else
		queued_user_highscore = nil
		queued_server_highscore = nil
	end
end

local difficulty_note_for_selection = function()
	local selected_name = normalize(get_selected_difficulty_name())
	local queued_name = NormalizeStepManiaServerDifficultyName(queued_difficulty_name)

	if selected_name ~= "" and queued_name ~= "" and selected_name ~= queued_name then
		return ("Queued: %s  •  Selected: %s"):format(queued_difficulty_name, get_selected_difficulty_name())
	end

	return ""
end

local try_change_difficulty = function(direction)
	if #available_chart_options <= 1 then return false end

	local now = GetTimeSinceStart()
	local same_direction = (last_diff_direction == direction)
	local within_window = last_diff_press_at > 0 and (now - last_diff_press_at) <= diff_double_press_window

	last_diff_direction = direction
	last_diff_press_at = now

	if not (same_direction and within_window) then
		return false
	end

	if direction == "up" then
		selected_index = ((selected_index - 2) % #available_chart_options) + 1
	else
		selected_index = (selected_index % #available_chart_options) + 1
	end

	last_diff_direction = nil
	last_diff_press_at = -1
	return true
end

local update_song_detail_strip = function(frame)
	local song = GAMESTATE:GetCurrentSong()
	local values = frame:GetChild("Values")
	local artist_value = values and values:GetChild("ArtistValue")
	local bpm_value = values and values:GetChild("BpmValue")
	local length_value = values and values:GetChild("LengthValue")

	if not song then
		if artist_value then artist_value:settext("") end
		if bpm_value then bpm_value:settext("") end
		if length_value then length_value:settext("") end
		return
	end

	if artist_value then
		artist_value:settext(song:GetDisplayArtist() or "")
	end

	if bpm_value then
		bpm_value:settext(StringifyDisplayBPMs() or "")
	end

	if length_value then
		local seconds = song:MusicLengthSeconds()
		if seconds then
			seconds = seconds / SL.Global.ActiveModifiers.MusicRate
			if seconds > 3600 then
				length_value:settext(math.floor(seconds / 3600) .. ":" .. SecondsToMMSS(seconds % 3600))
			else
				length_value:settext(SecondsToMSS(seconds))
			end
		else
			length_value:settext("")
		end
	end
end

local update_view = function(frame)
	local loaded_content = frame:GetChild("LoadedContent")
	local state_overlay = frame:GetChild("StateOverlay")
	local state_title = state_overlay and state_overlay:GetChild("StateTitle")
	local state_detail = state_overlay and state_overlay:GetChild("StateDetail")
	local state_footer = state_overlay and state_overlay:GetChild("StateFooter")
	local modal_overlay = frame:GetChild("ModalOverlay")

	if loaded_content then
		loaded_content:visible(queue_has_loaded_song())
	end

	if state_overlay then
		state_overlay:visible(not queue_has_loaded_song() and modal_mode == nil)
	end

	if modal_overlay then
		modal_overlay:visible(modal_mode ~= nil)
	end

		if modal_mode ~= nil and modal_overlay then
			local is_menu = (modal_mode == "menu")
			local modal_bg = modal_overlay:GetChild("ModalBackground")
			local modal_title_actor = modal_overlay:GetChild("ModalTitle")
			local modal_detail_actor = modal_overlay:GetChild("ModalDetail")
			if modal_bg then
				modal_bg:zoomto(is_menu and 310 or 620, is_menu and 164 or 230)
			end
		if modal_title_actor then
			modal_title_actor:visible(not is_menu)
			modal_title_actor:settext(is_menu and "" or modal_title)
		end
		if modal_detail_actor then
			modal_detail_actor:visible(not is_menu)
			modal_detail_actor:settext(is_menu and "" or modal_detail)
		end
		local options = modal_overlay:GetChild("Options")
		if options then
			for i = 1, 4 do
				local option = options:GetChild("Option" .. i)
				if option then
					local text = modal_options[i] or ""
					option:settext(text)
					option:visible(text ~= "")
					option:diffuse(i == modal_index and color("#ffffff") or color("#bbbbbb"))
				end
			end
		end
	end

	if queue_state == "loading" then
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

	if queue_state == "error" then
		if state_title then state_title:settext(queue_error_title) end
		if state_detail then state_detail:settext(queue_error_detail) end
		if state_footer then state_footer:settext(THEME:GetString("ScreenQueueReady", "ErrorFooter")) end
		return
	end

	local user_text = loaded_content and loaded_content:GetChild("UsernameText")
	local song_text = loaded_content and loaded_content:GetChild("SongText")
	local artist_text = loaded_content and loaded_content:GetChild("ArtistText")
	local detail_strip = loaded_content and loaded_content:GetChild("SongDetailStrip")
	local player_score_value = loaded_content and loaded_content:GetChild("PlayerScoreValue")
	local machine_score_value = loaded_content and loaded_content:GetChild("MachineScoreValue")
	local machine_holder = loaded_content and loaded_content:GetChild("MachineScoreHolder")
	local score_note = loaded_content and loaded_content:GetChild("ScoreNoteText")

	if not target_song then return end

	local subtitle = target_song:GetDisplaySubTitle() or ""
	local title = target_song:GetDisplayMainTitle() or ""
	if subtitle ~= "" then
		title = title .. "\n" .. subtitle
	end

	if user_text then
		user_text:settext(queued_player_name ~= "" and queued_player_name or THEME:GetString("ScreenQueueReady", "NoPlayer"))
	end
	if song_text then song_text:settext(title) end
	if artist_text then artist_text:settext(target_song:GetDisplayArtist() or "") end
	if detail_strip then update_song_detail_strip(detail_strip) end
	if player_score_value then
		player_score_value:settext("Personal Record: " .. format_high_score(queued_user_highscore))
	end
	if machine_score_value then
		machine_score_value:settext("Machine Record: " .. format_high_score(queued_server_highscore))
	end
	if machine_holder then machine_holder:settext(format_machine_holder(queued_server_highscore)) end
	if score_note then score_note:settext(difficulty_note_for_selection()) end
end

local transition_to = function(screen_name)
	if not top_screen then return end
	if type(input) == "function" then
		top_screen:RemoveInputCallback(input)
	end
	top_screen:SetNextScreenName(screen_name)
	top_screen:StartTransitioningScreen("SM_GoToNextScreen")
end

local process_current_body
local request_current

local scores_match = function(left, right)
	if left == nil and right == nil then return true end
	if type(left) ~= "table" or type(right) ~= "table" then return false end
	return tonumber(left.score) == tonumber(right.score) and tostring(left.grade or "") == tostring(right.grade or "")
end

local build_chart_options = function(song, chart_highscores)
	local steps_list = get_steps_for_current_style(song)
	if #steps_list == 0 then return {} end

	if type(chart_highscores) ~= "table" or #chart_highscores == 0 then
		local fallback_options = {}
		for _, steps in ipairs(steps_list) do
			fallback_options[#fallback_options+1] = {
				steps = steps,
				chart_id = nil,
				difficulty_name = GetStepManiaServerDifficultyNameForSteps(steps),
				meter = steps:GetMeter(),
				user_highscore = nil,
				server_highscore = nil,
			}
		end
		return fallback_options
	end

	local options = {}
	local used_steps = {}

	for _, entry in ipairs(chart_highscores) do
		local matched_index = nil

		for i, steps in ipairs(steps_list) do
			if not used_steps[i]
			and DoesStepManiaServerDifficultyMatch(steps, entry.difficulty_name)
			and tonumber(steps:GetMeter()) == tonumber(entry.meter)
			then
				matched_index = i
				break
			end
		end

		if not matched_index then
			for i, steps in ipairs(steps_list) do
				if not used_steps[i] and DoesStepManiaServerDifficultyMatch(steps, entry.difficulty_name) then
					matched_index = i
					break
				end
			end
		end

		if matched_index then
			used_steps[matched_index] = true
			options[#options+1] = {
				steps = steps_list[matched_index],
				chart_id = tonumber(entry.chart_id),
				difficulty_name = tostring(entry.difficulty_name or ""),
				meter = tonumber(entry.meter),
				user_highscore = entry.user_highscore,
				server_highscore = entry.server_highscore,
			}
		end
	end

	if #options == 0 then
		for _, steps in ipairs(steps_list) do
			options[#options+1] = {
				steps = steps,
				chart_id = nil,
				difficulty_name = GetStepManiaServerDifficultyNameForSteps(steps),
				meter = steps:GetMeter(),
				user_highscore = nil,
				server_highscore = nil,
			}
		end
	end

	return options
end

local find_initial_chart_index = function(options, song_data, user_highscore, server_highscore)
	local song_chart_id = type(song_data) == "table" and tonumber(song_data.chart_id) or nil
	if song_chart_id ~= nil then
		for i, option in ipairs(options) do
			if option.chart_id == song_chart_id then
				return i
			end
		end
	end

	local difficulty_name = type(song_data) == "table" and tostring(song_data.difficulty_name or "") or ""
	local difficulty_matches = {}
	for i, option in ipairs(options) do
		if NormalizeStepManiaServerDifficultyName(option.difficulty_name) == NormalizeStepManiaServerDifficultyName(difficulty_name) then
			difficulty_matches[#difficulty_matches+1] = i
		end
	end

	for _, i in ipairs(difficulty_matches) do
		local option = options[i]
		if scores_match(option.user_highscore, user_highscore) and scores_match(option.server_highscore, server_highscore) then
			return i
		end
	end

	if #difficulty_matches == 1 then
		return difficulty_matches[1]
	end

	for _, i in ipairs(difficulty_matches) do
		local option = options[i]
		if scores_match(option.user_highscore, user_highscore) or scores_match(option.server_highscore, server_highscore) then
			return i
		end
	end

	return difficulty_matches[1] or 1
end

local handle_queue_request_failure = function(frame, detail)
	queue_consecutive_failures = queue_consecutive_failures + 1

	if queue_consecutive_failures >= queue_failure_threshold then
		set_queue_error(THEME:GetString("ScreenQueueReady", "ConnectionError"), detail)
		close_modal()
		frame:playcommand("Refresh")
		return
	end

	queue_state = (queue_state == "empty") and "empty" or "loading"
	schedule_queue_poll()
	frame:playcommand("Refresh")
end

process_current_body = function(frame, body, force_apply)
	local context = queue_context_from_body(body)
	if not context then
		handle_queue_request_failure(frame, THEME:GetString("ScreenQueueReady", "InvalidResponse"))
		return
	end

	queue_consecutive_failures = 0
	SL.Global.ServerQueuePrefetch = body

	if not context.song then
		clear_queue_context()
		set_queue_empty()
		close_modal()
		schedule_queue_poll()
		frame:playcommand("Refresh")
		return
	end

	local queue_item_id = context.queue_item_id
	if not force_apply and current_queue_item_id ~= nil and queue_item_id == current_queue_item_id then
		close_modal()
		schedule_queue_poll()
		frame:playcommand("Refresh")
		return
	end

	local song = find_target_song(context.song.file_path)
	if not song then
		handle_queue_request_failure(frame, THEME:GetString("ScreenQueueReady", "MissingSong"):format(context.song.file_path))
		return
	end

	local chart_options = build_chart_options(song, body.chart_highscores)
	if #chart_options == 0 then
		handle_queue_request_failure(frame, THEME:GetString("ScreenQueueReady", "MissingChart"))
		return
	end

	target_song = song
	available_chart_options = chart_options
	selected_index = find_initial_chart_index(chart_options, context.song, context.user_highscore, context.server_highscore)
	current_queue_item_id = queue_item_id
	queued_song_path = context.song.file_path or ""
	queued_difficulty_name = context.song.difficulty_name or ""
	queued_player_name = context.player_name or ""
	queued_user_highscore = context.user_highscore
	queued_server_highscore = context.server_highscore
	queued_chart_highscores = type(body.chart_highscores) == "table" and body.chart_highscores or nil
	SL.Global.ServerQueueItemId = current_queue_item_id
	SL.Global.ServerQueueCurrent = body
	apply_selected_chart()
	update_highscores_for_selected_difficulty()
	set_queue_ready()
	close_modal()
	schedule_queue_poll()
	frame:playcommand("Refresh")
end

request_current = function(frame, show_loading, force_apply)
	if not frame then return end

	if show_loading then
		set_queue_loading()
		frame:playcommand("Refresh")
	end

	if current_request then
		current_request:Cancel()
		current_request = nil
	end

	local request, error_detail = build_server_request(CURRENT_ENDPOINT, "GET", nil, function(response)
		current_request = nil
		local body = safe_json_decode(response and response.body or "")

		if not response or response.statusCode ~= 200 then
			handle_queue_request_failure(frame, get_response_error_detail(response, body))
			return
		end

		process_current_body(frame, body, force_apply)
	end)

	if not request then
		set_queue_error(THEME:GetString("ScreenQueueReady", "ConnectionError"), error_detail)
		frame:playcommand("Refresh")
		return
	end

	current_request_started_at = GetTimeSinceStart()
	queue_next_poll_at = -1
	current_request = request
end

local action_error_to_screen = function(frame, detail)
	set_queue_error(THEME:GetString("ScreenQueueReady", "ActionErrorTitle"), detail)
	close_modal()
	frame:playcommand("Refresh")
end

local request_start = function(frame)
	local steps = get_selected_steps()
	if not target_song or not steps then return end

	pending_action = "start"

	local request_body = BuildStepManiaServerSongRequestBody({
		chart_id = get_selected_chart_id(),
	})

	local request, error_detail = build_server_request(START_ENDPOINT, "POST", request_body, function(response)
		local body = safe_json_decode(response and response.body or "")

		if not response or response.statusCode ~= 200 then
			pending_action = nil
			action_error_to_screen(frame, get_response_error_detail(response, body))
			return
		end

		SL.Global.ServerQueueStartBaseline = {
			chart_id = request_body.chart_id,
			difficulty_name = get_selected_difficulty_name(),
			user_highscore = body and body.user_highscore or nil,
			server_highscore = body and body.server_highscore or nil,
		}
		SL.Global.ServerQueueFinishResult = nil
		SL.Global.ServerQueueSelectedChartId = request_body.chart_id
		SL.Global.ServerQueueSelectedDifficultyName = get_selected_difficulty_name()

		local snd = frame:GetChild("start_sound")
		if snd then snd:play() end

		GAMESTATE:SetCurrentPlayMode("PlayMode_Regular")
		local song_options = GAMESTATE:GetSongOptionsObject("ModsLevel_Preferred")
		if song_options then
			song_options:MusicRate(SL.Global.ActiveModifiers.MusicRate)
		end

		SL.Global.ServerModeActive = true
		SL.Global.GameMode = "ITG"
		pending_action = nil
		close_modal()
		transition_to("ScreenGameplay")
	end)

	if not request then
		pending_action = nil
		action_error_to_screen(frame, error_detail)
	end
end

local request_skip = function(frame)
	open_busy_modal(
		THEME:GetString("ScreenQueueReady", "SkippingTitle"),
		THEME:GetString("ScreenQueueReady", "SkippingDetail"),
		"skip"
	)
	frame:playcommand("Refresh")

	local request, error_detail = build_server_request(
		SKIP_ENDPOINT,
		"POST",
		BuildStepManiaServerSongRequestBody({}),
		function(response)
			local body = safe_json_decode(response and response.body or "")

			if not response or response.statusCode ~= 200 then
				action_error_to_screen(frame, get_response_error_detail(response, body))
				return
			end

			clear_queue_context()
			request_current(frame, false, true)
		end
	)

	if not request then
		action_error_to_screen(frame, error_detail)
	end
end

local request_song_options = function()
	SL.Global.ScreenAfter.PlayerOptions = "ScreenQueueReady"
	close_modal()
	transition_to("ScreenPlayerOptions")
end

input = function(event)
	if not event or event.type == "InputEventType_Release" then return false end

	if pending_action ~= nil then
		return true
	end

	if modal_mode == "busy" then
		return true
	end

	if modal_mode == "menu" then
		if event.GameButton == "MenuUp" or event.GameButton == "MenuLeft" then
			modal_index = ((modal_index - 2) % #modal_options) + 1
			top_screen:GetChild("Underlay"):playcommand("Refresh")
			local snd = top_screen:GetChild("Underlay"):GetChild("change_sound")
			if snd then snd:play() end
			return true
		end

		if event.GameButton == "MenuDown" or event.GameButton == "MenuRight" then
			modal_index = (modal_index % #modal_options) + 1
			top_screen:GetChild("Underlay"):playcommand("Refresh")
			local snd = top_screen:GetChild("Underlay"):GetChild("change_sound")
			if snd then snd:play() end
			return true
		end

		if is_back_button(event) then
			close_modal()
			top_screen:GetChild("Underlay"):playcommand("Refresh")
			return true
		end

		if is_start_button(event) then
			if modal_index == 1 then
				close_modal()
				top_screen:GetChild("Underlay"):playcommand("Refresh")
			elseif modal_index == 2 then
				request_song_options()
			else
				if modal_index == 3 then
					request_skip(top_screen:GetChild("Underlay"))
				else
					SL.Global.ServerModeActive = false
					clear_server_session_state()
					close_modal()
					transition_to("ScreenTitleMenu")
				end
			end
			return true
		end

		return true
	end

	if queue_state == "error" then
		if is_start_button(event) then
			request_current(top_screen:GetChild("Underlay"), true, true)
			return true
		end

		if is_back_button(event) then
			SL.Global.ServerModeActive = false
			clear_server_session_state()
			transition_to("ScreenTitleMenu")
			return true
		end

		return true
	end

	if queue_state == "empty" then
		if is_back_button(event) then
			SL.Global.ServerModeActive = false
			clear_server_session_state()
			transition_to("ScreenTitleMenu")
			return true
		end
		return true
	end

	if queue_state == "loading" then
		if is_back_button(event) then
			SL.Global.ServerModeActive = false
			clear_server_session_state()
			transition_to("ScreenTitleMenu")
			return true
		end
		return true
	end

	if event.GameButton == "MenuUp" and try_change_difficulty("up") then
		apply_selected_chart()
		update_highscores_for_selected_difficulty()
		top_screen:GetChild("Underlay"):playcommand("Refresh")
		return true
	end

	if event.GameButton == "MenuDown" and try_change_difficulty("down") then
		apply_selected_chart()
		update_highscores_for_selected_difficulty()
		top_screen:GetChild("Underlay"):playcommand("Refresh")
		return true
	end

	if is_back_button(event) then
		open_back_menu()
		top_screen:GetChild("Underlay"):playcommand("Refresh")
		local snd = top_screen:GetChild("Underlay"):GetChild("change_sound")
		if snd then snd:play() end
		return true
	end

	if is_start_button(event) then
		if GAMESTATE:GetNumSidesJoined() == 0 then
			local joined = event.PlayerNumber and GAMESTATE:JoinInput(event.PlayerNumber)
			if not joined then
				GAMESTATE:JoinPlayer(PLAYER_1)
			end
		end

		request_start(top_screen:GetChild("Underlay"))
		return true
	end

	return false
end

local t = Def.ActorFrame{
	OnCommand=function(self)
		top_screen = SCREENMAN:GetTopScreen()
		local continuing_server_flow = SL.Global.ServerModeActive
		SL.Global.ServerModeActive = true
		SL.Global.GameMode = "Server"
		SL.Global.ScreenAfter.PlayerOptions = "ScreenGameplay"
		GAMESTATE:SetCurrentPlayMode("PlayMode_Regular")

		local song_options = GAMESTATE:GetSongOptionsObject("ModsLevel_Preferred")
		if song_options then
			song_options:MusicRate(SL.Global.ActiveModifiers.MusicRate)
		end

		if GAMESTATE:GetNumSidesJoined() == 0 then
			GAMESTATE:JoinPlayer(PLAYER_1)
		end

		if top_screen then
			top_screen:AddInputCallback(input)
		end

		self:SetUpdateFunction(function(actor)
			local now = GetTimeSinceStart()

			if current_request and (now - current_request_started_at) >= queue_timeout_seconds then
				current_request:Cancel()
				current_request = nil
				handle_queue_request_failure(actor, THEME:GetString("ScreenQueueReady", "RequestTimedOut"):format(queue_timeout_seconds))
				return
			end

			if queue_state == "ready" and target_song and preview_song_dir == "" and next_preview_attempt_at > -1 and now >= next_preview_attempt_at then
				play_song_preview(target_song)
				if preview_song_dir == "" then
					next_preview_attempt_at = now + preview_retry_interval_seconds
				end
			end

			if modal_mode ~= nil then
				return
			end

			if queue_state ~= "error" and not current_request and queue_next_poll_at > 0 and now >= queue_next_poll_at then
				request_current(actor, false, false)
			end
		end)

		self:playcommand("Refresh")

		if not continuing_server_flow then
			SL.Global.ServerQueuePrefetch = nil
		end

		if type(SL.Global.ServerQueuePrefetch) == "table" then
			process_current_body(self, SL.Global.ServerQueuePrefetch, true)
		else
			request_current(self, true, true)
		end
	end,

	OffCommand=function(self)
		if current_request then
			current_request:Cancel()
			current_request = nil
		end
		stop_song_preview()
		self:SetUpdateFunction(nil)
		queue_next_poll_at = -1
		if top_screen and type(input) == "function" then
			top_screen:RemoveInputCallback(input)
		end
	end,

	RefreshCommand=function(self)
		update_view(self)
	end,

	Def.ActorFrame{
		Name="LoadedContent",
		Def.ActorFrame{
			InitCommand=function(self)
				if IsUsingWideScreen() then
					self:zoom(0.7655):xy(_screen.cx - 170, 96)
				else
					self:zoom(0.75):xy(_screen.cx - 166, 96)
				end
			end,

			Def.Sprite{
				Name="ServerBannerFallback",
				Texture=GetFallbackBanner(),
				InitCommand=function(self)
					self:setsize(banner_width, banner_height)
				end
			},
		},

		Def.ActorFrame{
			Name="SongDetailStrip",
			InitCommand=function(self)
				self:xy(_screen.cx - (IsUsingWideScreen() and 170 or 165), _screen.cy - 55)
			end,

			Def.Quad{
				InitCommand=function(self)
					self:setsize(IsUsingWideScreen() and 320 or 310, 50):diffuse(color("#1e282f"))
					if ThemePrefs.Get("RainbowMode") then self:diffusealpha(0.9) end
					if ThemePrefs.Get("VisualStyle") == "Technique" then self:diffusealpha(0.5) end
				end
			},

			Def.ActorFrame{
				Name="Values",
				InitCommand=function(self) self:xy(-110, -6) end,

				LoadFont("Common Normal")..{
					Text=THEME:GetString("SongDescription", "Artist"):upper(),
					InitCommand=function(self) self:align(1,0):y(-11):maxwidth(44):diffuse(0.5,0.5,0.5,1) end,
				},
				LoadFont("Common Normal")..{
					Name="ArtistValue",
					InitCommand=function(self) self:align(0,0):xy(5,-11):maxwidth((IsUsingWideScreen() and 320 or 310) - 60) end,
				},

				LoadFont("Common Normal")..{
					Text=THEME:GetString("SongDescription", "BPM"):upper(),
					InitCommand=function(self) self:align(1,0):y(10):diffuse(0.5,0.5,0.5,1) end,
				},
				LoadFont("Common Normal")..{
					Name="BpmValue",
					InitCommand=function(self) self:align(0,0.5):xy(5,17):vertspacing(-8) end,
				},

				LoadFont("Common Normal")..{
					Text=THEME:GetString("SongDescription", "Length"):upper(),
					InitCommand=function(self)
						self:align(1,0):diffuse(0.5,0.5,0.5,1)
						self:x((IsUsingWideScreen() and 320 or 310) - 130):y(10)
					end
				},
				LoadFont("Common Normal")..{
					Name="LengthValue",
					InitCommand=function(self) self:align(0,0):xy((IsUsingWideScreen() and 320 or 310) - 125, 10) end,
				},
			},
		},

		-- Right info panel
		Def.Quad{
			InitCommand=function(self)
				local w = IsUsingWideScreen() and 370 or 290
				local cx = _screen.cx + (IsUsingWideScreen() and 235 or 185)
				self:xy(cx, 178):zoomto(w, 246):diffuse(color("#000000")):diffusealpha(0.55)
			end
		},

		LoadFont("Common Normal")..{
			Name="UsernameText",
			InitCommand=function(self)
				self:xy(_screen.cx + (IsUsingWideScreen() and 62 or 52), 86)
					:zoom(1.04):horizalign(0)
					:maxwidth(IsUsingWideScreen() and 290 or 220)
					:diffuse(color("#9ca3af"))
			end
		},

		LoadFont("Common Normal")..{
			Name="SongText",
			InitCommand=function(self)
				self:xy(_screen.cx + (IsUsingWideScreen() and 62 or 52), 114)
					:zoom(1.16):horizalign(0):vertalign(0)
					:maxwidth(IsUsingWideScreen() and 290 or 220)
			end
		},

		LoadFont("Common Normal")..{
			Name="ArtistText",
			InitCommand=function(self)
				self:xy(_screen.cx + (IsUsingWideScreen() and 62 or 52), 174)
					:zoom(0.96):horizalign(0)
					:maxwidth(IsUsingWideScreen() and 300 or 230)
					:diffuse(color("#9ca3af"))
			end
		},

		LoadFont("Common Normal")..{
			Name="PlayerScoreValue",
			InitCommand=function(self)
				self:xy(_screen.cx + (IsUsingWideScreen() and 62 or 52), 212)
					:zoom(0.96):horizalign(0)
					:maxwidth(IsUsingWideScreen() and 300 or 230)
			end
		},

		LoadFont("Common Normal")..{
			Name="MachineScoreValue",
			InitCommand=function(self)
				self:xy(_screen.cx + (IsUsingWideScreen() and 62 or 52), 248)
					:zoom(0.96):horizalign(0)
					:maxwidth(IsUsingWideScreen() and 300 or 230)
			end
		},

		LoadFont("Common Normal")..{
			Name="MachineScoreHolder",
			InitCommand=function(self)
				self:xy(_screen.cx + (IsUsingWideScreen() and 62 or 52), 282)
					:zoom(0.80):horizalign(0)
					:maxwidth(IsUsingWideScreen() and 320 or 250)
					:diffuse(color("#cfcfcf"))
			end
		},

		LoadFont("Common Normal")..{
			Name="ScoreNoteText",
			InitCommand=function(self)
				self:xy(_screen.cx + (IsUsingWideScreen() and 62 or 52), 314)
					:zoom(0.72):horizalign(0)
					:maxwidth(IsUsingWideScreen() and 360 or 280)
					:diffuse(color("#9ca3af"))
			end
		},

		LoadActor(THEME:GetPathB("ScreenSelectMusic", "overlay/PaneDisplay.lua")),
		LoadActor(THEME:GetPathB("ScreenSelectMusic", "overlay/PerPlayer/default.lua")),
		LoadActor(THEME:GetPathB("ScreenSelectMusic", "overlay/StepsDisplayList/default.lua")),
	},

	Def.ActorFrame{
		Name="StateOverlay",
		InitCommand=function(self) self:visible(false) end,

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

	Def.ActorFrame{
		Name="ModalOverlay",
		InitCommand=function(self) self:visible(false) end,

		Def.Quad{
			Name="ModalBackground",
			InitCommand=function(self)
				self:Center():zoomto(620, 230):diffuse(color("#000000")):diffusealpha(0.88)
			end
		},
		LoadFont("Common Bold")..{
			Name="ModalTitle",
			InitCommand=function(self)
				self:xy(_screen.cx, _screen.cy - 58):zoom(0.82):maxwidth(560)
			end
		},
		LoadFont("Common Normal")..{
			Name="ModalDetail",
			InitCommand=function(self)
				self:xy(_screen.cx, _screen.cy - 16):zoom(0.65):maxwidth(760):wrapwidthpixels(740):diffuse(color("#d0d0d0"))
			end
		},
		Def.ActorFrame{
			Name="Options",
			LoadFont("Common Normal")..{
				Name="Option1",
				InitCommand=function(self)
					self:xy(_screen.cx, _screen.cy - 54):zoom(0.82):maxwidth(400)
				end
			},
			LoadFont("Common Normal")..{
				Name="Option2",
				InitCommand=function(self)
					self:xy(_screen.cx, _screen.cy - 18):zoom(0.82):maxwidth(400)
				end
			},
			LoadFont("Common Normal")..{
				Name="Option3",
				InitCommand=function(self)
					self:xy(_screen.cx, _screen.cy + 18):zoom(0.82):maxwidth(400)
				end
			},
			LoadFont("Common Normal")..{
				Name="Option4",
				InitCommand=function(self)
					self:xy(_screen.cx, _screen.cy + 54):zoom(0.82):maxwidth(400)
				end
			},
		},
	},
}

t[#t+1] = LoadActor(THEME:GetPathS("ScreenSelectMaster", "change"))..{ Name="change_sound", IsAction=true, SupportPan=false }
t[#t+1] = LoadActor(THEME:GetPathS("common", "start"))..{ Name="start_sound", IsAction=true, SupportPan=false }

return t
