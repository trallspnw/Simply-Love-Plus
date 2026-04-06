-- Minimal overlay for ScreenQueueReady.
-- Overrides the ScreenSelectMusic overlay to prevent its BannerProxy (which shows
-- the previous song's banner) and other SSM-specific UI from appearing.
-- The underlay handles all banner, pane, and step-display rendering for this screen.

return Def.ActorFrame{
	InitCommand=function(self)
		SL.Global.GameplayReloadCheck = false
	end,
}
