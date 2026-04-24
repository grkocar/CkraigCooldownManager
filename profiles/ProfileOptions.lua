-- ============================================================
-- CkraigCooldownManager :: Profiles :: ProfileOptions
-- ============================================================
-- AceConfig options table for the profile panel,
-- including import / export via AceSerializer.
-- Split from ProfileManager for cleaner code.
-- ============================================================

local ProfileManager = _G.CkraigProfileManager
local LibDualSpec = LibStub("LibDualSpec-1.0", true)

function ProfileManager:CreateProfileOptions()
    local AceConfig = LibStub("AceConfig-3.0")
    local AceConfigDialog = LibStub("AceConfigDialog-3.0")
    local AceSerializer = LibStub("AceSerializer-3.0")
    local AceDBOptions = LibStub("AceDBOptions-3.0")

    if not AceConfig or not AceConfigDialog or not AceDBOptions then
        print("ProfileManager: AceConfig libraries not available, profile management disabled")
        return
    end

    local options = AceDBOptions:GetOptionsTable(self.db)
    AceConfig:RegisterOptionsTable("CkraigCooldownManager Profiles", options)

    if LibDualSpec then
        LibDualSpec:EnhanceOptions(options, self.db)
    end

    -- Import / Export
    if AceSerializer then
        local function GetEditBox(dlg)
            return dlg.editBox or dlg.EditBox
        end

        StaticPopupDialogs["CKRAIG_PROFILE_EXPORT"] = {
            text = "Copy this profile export string:",
            button1 = "Close",
            hasEditBox = true,
            editBoxWidth = 400,
            OnShow = function(self, data)
                if not data or data == "" then
                    if ProfileManager and ProfileManager.db and ProfileManager.db.profile then
                        data = LibStub("AceSerializer-3.0"):Serialize(ProfileManager.db.profile)
                        self.data = data
                    end
                end
                local box = GetEditBox(self)
                if box then
                    box:SetText(data or "")
                    box:HighlightText()
                    box:SetFocus()
                end
            end,
            OnAccept = function() end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }

        StaticPopupDialogs["CKRAIG_PROFILE_IMPORT"] = {
            text = "Paste the profile import string:",
            button1 = "Import",
            button2 = "Cancel",
            hasEditBox = true,
            editBoxWidth = 400,
            OnShow = function(self)
                local box = GetEditBox(self)
                if box then
                    box:SetText("")
                    box:SetFocus()
                end
            end,
            OnAccept = function(self)
                local box = GetEditBox(self)
                local value = box and box:GetText() or ""
                local success, data = AceSerializer:Deserialize(value)
                if success and type(data) == "table" then
                    for k in pairs(ProfileManager.db.profile) do
                        ProfileManager.db.profile[k] = nil
                    end
                    for k, v in pairs(data) do
                        ProfileManager.db.profile[k] = v
                    end
                    ProfileManager:EnsureDefaults()
                    ProfileManager:OnProfileChanged()
                    print("Profile imported and applied successfully.")
                else
                    print("Invalid import string")
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }

        options.args.currentprofile = {
            type = "description",
            name = function() return "Profile: " .. ProfileManager.db:GetCurrentProfile() end,
            order = 50,
        }

        options.args.importexport = {
            type = "group",
            name = "Import/Export",
            order = 100,
            args = {
                export = {
                    type = "execute",
                    name = "Export Profile",
                    desc = "Opens a popup with the export string to copy",
                    func = function()
                        local serialized = AceSerializer:Serialize(ProfileManager.db.profile)
                        StaticPopup_Show("CKRAIG_PROFILE_EXPORT", serialized)
                    end,
                },
                import = {
                    type = "execute",
                    name = "Import Profile",
                    desc = "Opens a popup to paste an import string",
                    func = function()
                        StaticPopup_Show("CKRAIG_PROFILE_IMPORT")
                    end,
                },
            },
        }
    end

    -- Register as standalone Blizzard panel
    if not _G.CkraigProfileManagerPanel or not _G.CkraigProfileManagerPanel._addedToOptions then
        local panel = AceConfigDialog:AddToBlizOptions("CkraigCooldownManager Profiles", "Ckraig Profiles")
        _G.CkraigProfileManagerPanel = panel
        self.profilePanel = panel
        panel._addedToOptions = true
    else
        self.profilePanel = _G.CkraigProfileManagerPanel
    end
end
