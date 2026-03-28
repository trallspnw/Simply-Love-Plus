local QUEUE_ENDPOINT = "/api/game/song/current"

local top_screen
local request
local request_started_at = -1
local timeout_seconds = 10
local state = "loading"
local error_detail = ""

local normalize = function(path)
	return (path or ""):gsub("\\", "/"):gsub("^/*", ""):gsub("/*$", ""):lower()
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

local safe_json_decode = function(body)
	if type(body) ~= "string" or body == "" then
		return nil
	end

	local ok, decoded = pcall(JsonDecode, body)
	return ok and decoded or nil
end

local get_response_error_detail = function(response, body)
	if response and response.error and ToEnumShortString(response.error) == "Timeout" then
		return THEME:GetString("ScreenServer2Load", "RequestTimedOut"):format(timeout_seconds)
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
		return THEME:GetString("ScreenServer2Load", "RequestStatus"):format(response.statusCode)
	end

	return THEME:GetString("ScreenServer2Load", "RequestFailed")
end

local set_error = function(detail)
	state = "error"
	error_detail = detail or THEME:GetString("ScreenServer2Load", "RequestFailed")
	if top_screen then
		top_screen:GetChild("Underlay"):playcommand("Refresh")
	end
end

local apply_selection = function(song, steps)
	GAMESTATE:SetCurrentSong(song)

	for pn in ivalues(GAMESTATE:GetHumanPlayers()) do
		GAMESTATE:SetCurrentSteps(pn, steps)
		GAMESTATE:SetPreferredDifficulty(pn, steps:GetDifficulty())
	end
end

local transition_to_select_music = function()
	if not top_screen then return end
	top_screen:SetNextScreenName("ScreenSelectMusic")
	top_screen:StartTransitioningScreen("SM_GoToNextScreen")
end

local fetch_server_song

fetch_server_song = function(actor)
	local config = (SL.Global and SL.Global.StepManiaServer) or {}
	local base_url = config.Url or ""
	local token = config.Token or ""

	state = "loading"
	error_detail = ""
	request_started_at = GetTimeSinceStart()
	SL.Global.ServerQueueItemId = nil

	if request then
		request:Cancel()
		request = nil
	end

	if base_url == "" or token == "" then
		set_error(THEME:GetString("ScreenServer2Load", "MissingConfig"))
		return
	end

	actor:playcommand("Refresh")

	request = NETWORK:HttpRequest{
		url=base_url .. QUEUE_ENDPOINT,
		method="GET",
		headers={
			Authorization="Bearer " .. token,
		},
		connectTimeout=timeout_seconds,
		transferTimeout=timeout_seconds,
		onResponse=function(response)
			request = nil
			local body = safe_json_decode(response and response.body or "")

			if not response or response.statusCode ~= 200 then
				set_error(get_response_error_detail(response, body))
				return
			end

			if type(body) ~= "table" then
				set_error(THEME:GetString("ScreenServer2Load", "InvalidResponse"))
				return
			end

			if type(body.song) ~= "table" or type(body.song.file_path) ~= "string" or body.song.file_path == "" then
				set_error(THEME:GetString("ScreenServer2Load", "NoQueuedSong"))
				return
			end

			SL.Global.ServerQueueItemId = body.queue_item_id

			local song = find_target_song(body.song.file_path)
			if not song then
				set_error(THEME:GetString("ScreenServer2Load", "MissingSong"):format(body.song.file_path))
				return
			end

			local available_steps = get_steps_for_current_style(song)
			if #available_steps == 0 then
				set_error(THEME:GetString("ScreenServer2Load", "MissingChart"))
				return
			end

			local index = find_step_index_for_difficulty(available_steps, body.song.difficulty_name or "") or 1
			apply_selection(song, available_steps[index])
			state = "ready"
			transition_to_select_music()
		end,
	}
end

local input = function(event)
	if not event or event.type == "InputEventType_Release" then return false end
	if state ~= "error" then return false end

	if event.GameButton == "Start" then
		local underlay = top_screen and top_screen:GetChild("Underlay")
		if underlay then
			fetch_server_song(underlay)
		end
		return true
	end

	if event.GameButton == "Back" then
		top_screen:SetNextScreenName("ScreenTitleMenu")
		top_screen:StartTransitioningScreen("SM_GoToNextScreen")
		return true
	end

	return false
end

return Def.ActorFrame{
	OnCommand=function(self)
		top_screen = SCREENMAN:GetTopScreen()
		if top_screen then
			top_screen:AddInputCallback(input)
		end

		self:SetUpdateFunction(function(actor)
			local now = GetTimeSinceStart()
			if request and (now - request_started_at) >= timeout_seconds then
				request:Cancel()
				request = nil
				set_error(THEME:GetString("ScreenServer2Load", "RequestTimedOut"):format(timeout_seconds))
			end
		end)

		fetch_server_song(self)
	end,

	OffCommand=function(self)
		if request then
			request:Cancel()
			request = nil
		end
		self:SetUpdateFunction(nil)
		if top_screen then
			top_screen:RemoveInputCallback(input)
		end
	end,

	RefreshCommand=function(self)
		local title = self:GetChild("Title")
		local detail = self:GetChild("Detail")
		local footer = self:GetChild("Footer")

		if state == "loading" then
			title:settext(THEME:GetString("ScreenServer2Load", "LoadingTitle"))
			detail:settext(THEME:GetString("ScreenServer2Load", "LoadingPrompt"))
			footer:settext("")
		elseif state == "error" then
			title:settext(THEME:GetString("ScreenServer2Load", "ErrorTitle"))
			detail:settext(error_detail)
			footer:settext(("%s  %s"):format(
				THEME:GetString("ScreenServer2Load", "Retry"),
				THEME:GetString("ScreenServer2Load", "Back")
			))
		else
			title:settext("")
			detail:settext("")
			footer:settext("")
		end
	end,

	LoadFont("Common Bold")..{
		Name="Title",
		InitCommand=function(self)
			self:xy(_screen.cx, _screen.cy - 30):zoom(0.75)
		end
	},
	LoadFont("Common Normal")..{
		Name="Detail",
		InitCommand=function(self)
			self:xy(_screen.cx, _screen.cy + 10):zoom(0.6):maxwidth(900)
		end
	},
	LoadFont("Common Normal")..{
		Name="Footer",
		InitCommand=function(self)
			self:xy(_screen.cx, _screen.cy + 55):zoom(0.5):diffuse(color("#bbbbbb")):maxwidth(1000)
		end
	},
}
