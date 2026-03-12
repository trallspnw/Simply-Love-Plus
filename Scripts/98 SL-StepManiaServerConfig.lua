StepManiaServerConfig = {
	FilePath = "Save/StepManiaServer.ini",
	SectionName = "StepManiaServer",
	defaults = {
		Url = "",
		Token = "",
	},
}

local function trim(value)
	if type(value) ~= "string" then
		return ""
	end

	return value:match("^%s*(.-)%s*$") or ""
end

local function sanitize(config)
	local url = trim(config.Url):gsub("/+$", "")
	local token = trim(config.Token)

	return {
		Url = url,
		Token = token,
	}
end

function StepManiaServerConfig.Get()
	local contents = IniFile.ReadFile(StepManiaServerConfig.FilePath) or {}
	local section = contents[StepManiaServerConfig.SectionName] or {}
	local merged = {
		Url = section.Url or StepManiaServerConfig.defaults.Url,
		Token = section.Token or StepManiaServerConfig.defaults.Token,
	}

	return sanitize(merged)
end

function StepManiaServerConfig.Save(config)
	local sanitized = sanitize(config or StepManiaServerConfig.defaults)

	IniFile.WriteFile(StepManiaServerConfig.FilePath, {
		[StepManiaServerConfig.SectionName] = sanitized
	})

	return sanitized
end

function StepManiaServerConfig.Init()
	return StepManiaServerConfig.Save(StepManiaServerConfig.Get())
end

StepManiaServerConfig.Init()
