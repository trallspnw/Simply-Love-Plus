-- Server Mode results page: the player's score, and how it compares with their
-- personal record and the server record once StepMania Server has recorded it.
-- The server queue flow (ScreenEvaluationStageServer) sends the record lines
-- with the ServerQueueResultsChanged message.

local player, controller = unpack(...)

if not SL.Global.ServerModeActive then return end

local text_width = 290

return Def.ActorFrame{
	ServerQueueResultsChangedMessageCommand=function(self, params)
		if not params or params.player ~= player then return end

		local primary_zoom = params.primary_zoom or 0.45
		self:GetChild("RecordPrimary")
			:settext(params.primary or "")
			:diffuse(color(params.primary_color or "#d8d8d8"))
			:zoom(primary_zoom)
			:maxwidth(text_width / primary_zoom)
		self:GetChild("RecordSecondary"):settext(params.secondary or "")
	end,

	LoadActor(THEME:GetPathB("ScreenEvaluation", "common/Panes/Pane1/Percentage.lua"), {player, controller}),

	LoadFont("Common Bold")..{
		Name="RecordPrimary",
		InitCommand=function(self)
			self:y(_screen.cy + 30):zoom(0.45):maxwidth(text_width / 0.45)
		end,
	},

	LoadFont("Common Normal")..{
		Name="RecordSecondary",
		InitCommand=function(self)
			self:y(_screen.cy + 66):zoom(0.9):maxwidth(text_width / 0.9):diffuse(color("#d8d8d8"))
		end,
	},
}
