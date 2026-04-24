GlowManager.lua Usage Guide

1. Require the GlowManager module in your Lua files:
   local GlowManager = require("GlowManager")

2. To show a glow on a frame:
   GlowManager:ShowGlow(frame, { style = "custom", color = {1, 0, 0, 1} })
   -- or for default LibButtonGlow:
   GlowManager:ShowGlow(frame)

3. To hide a glow from a frame:
   GlowManager:HideGlow(frame, { style = "custom" })
   -- or for default LibButtonGlow:
   GlowManager:HideGlow(frame)

4. You can customize color, lines, frequency, length, thickness, xOffset, yOffset for custom glows.

5. Replace all direct calls to LibButtonGlow or LibCustomGlow in your code with GlowManager:ShowGlow/HideGlow for consistency.
