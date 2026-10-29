-- FamQuestPort: stock QuestLogFrame + optional ForeverUI quest pane.
local PREFIX = "FQP"
local lastClick = 0

local function SelectedQuestId(forced)
  local index = forced or GetQuestLogSelection()
  if not index or index == 0 then return nil end
  local title, _, _, _, isHeader = GetQuestLogTitle(index)
  if not title or isHeader then return nil end
  local link = GetQuestLink(index)
  local id = link and tonumber(link:match("|Hquest:(%d+)"))
  return id, title
end

local function Request(forced)
  local id, title = SelectedQuestId(type(forced) == "number" and forced or nil)
  if not id then
    UIErrorsFrame:AddMessage("Pick a quest first!", 1.0, 0.82, 0.0)
    return
  end
  if GetTime() - lastClick < 2 then return end      -- no double-click spam; the server has the real cooldown
  lastClick = GetTime()
  SendAddonMessage(PREFIX, "TP:" .. id, "WHISPER", UnitName("player"))
end

local function MakeButton(name, parent)
  local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
  b:SetWidth(110); b:SetHeight(21)
  b:SetText("Teleport Near")
  b:SetScript("OnClick", Request)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Teleport Near")
    GameTooltip:AddLine("Teleports you close to this quest's goal\n(or to the turn-in when it's done).", 1, 1, 1, true)
    GameTooltip:AddLine("Stand still for a moment. Not in fights, dungeons\nor battlegrounds. Short cooldown.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

local mainBtn, detailBtn
local function Refresh()
  local id = SelectedQuestId()
  if mainBtn then if id then mainBtn:Show() else mainBtn:Hide() end end
  if detailBtn then if id then detailBtn:Show() else detailBtn:Hide() end end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("QUEST_LOG_UPDATE")
f:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_LOGIN" then
    if QuestLogFrame and not mainBtn then
      mainBtn = MakeButton("FamQuestPortButton", QuestLogFrame)
      if QuestLogFrameShowMapButton then
        mainBtn:SetPoint("RIGHT", QuestLogFrameShowMapButton, "LEFT", -6, 0)
      else
        mainBtn:SetPoint("TOPRIGHT", QuestLogFrame, "TOPRIGHT", -150, -38)
      end
      QuestLogFrame:HookScript("OnShow", Refresh)
    end
    if QuestLogDetailFrame and not detailBtn then
      detailBtn = MakeButton("FamQuestPortDetailButton", QuestLogDetailFrame)
      detailBtn:SetPoint("BOTTOMLEFT", QuestLogDetailFrame, "BOTTOMLEFT", 20, 14)
      QuestLogDetailFrame:HookScript("OnShow", Refresh)
    end
    if QuestLog_SetSelection then hooksecurefunc("QuestLog_SetSelection", Refresh) end
  end
  Refresh()
end)

SLASH_FAMQUESTPORT1 = "/tpnear"
SlashCmdList["FAMQUESTPORT"] = function() Request() end

-- ForeverUI (2026-10-24, v2 03:40): its quest log is its own pane on the world map
-- (ForeverUIQuestDetailsFrame, created when ForeverUI loads; the stock QuestLogFrame stays
-- hidden, so the buttons above never show). v1 put the button above Track, which is inside
-- ForeverUI's rewards box (frame level +50) and ran its show check from OnShow, before
-- ForeverUI sets d.index, so it stayed hidden. v2: button in the top banner, right of Back,
-- above the border (level +100), refreshed from ForeverUI.QuestLog.updateDetailsButtons.
local fuiBtn
local function FUIUpdate()
  local d = _G.ForeverUIQuestDetailsFrame
  if not (fuiBtn and d) then return end
  local idx = d.index
  local ok = d:IsShown() and idx and idx > 0 and GetQuestLogTitle(idx) and not select(5, GetQuestLogTitle(idx))
  if ok then
    local lvl = (d.edge and d.edge:GetFrameLevel() or d:GetFrameLevel() + 100) + 5
    if fuiBtn:GetFrameLevel() < lvl then fuiBtn:SetFrameLevel(lvl) end
    fuiBtn:Show()
  else
    fuiBtn:Hide()
  end
end
local function AttachForeverUI()
  if fuiBtn then return true end
  local d = _G.ForeverUIQuestDetailsFrame
  if not d then return false end
  fuiBtn = MakeButton("FamQuestPortFUIButton", d)
  fuiBtn:SetScript("OnClick", function() Request(d.index) end)
  fuiBtn:ClearAllPoints()
  local back = _G.ForeverUIQuestDetailsBackButton
  if back and back:GetParent() then
    fuiBtn:SetPoint("RIGHT", back:GetParent(), "RIGHT", -12, 4)   -- same row as Back
  else
    fuiBtn:SetPoint("TOPRIGHT", d, "TOPRIGHT", -14, -12)
  end
  local lvl = d:GetFrameLevel() + 100
  if d.edge then lvl = d.edge:GetFrameLevel() end
  fuiBtn:SetFrameStrata(d:GetFrameStrata())
  fuiBtn:SetFrameLevel(lvl + 5)
  fuiBtn:Hide()
  d:HookScript("OnShow", FUIUpdate)
  d:HookScript("OnHide", function() fuiBtn:Hide() end)
  local J = ForeverUI and ForeverUI.QuestLog
  if J and type(J.updateDetailsButtons) == "function" then
    hooksecurefunc(J, "updateDetailsButtons", FUIUpdate)
  end
  FUIUpdate()
  return true
end
local fw = CreateFrame("Frame")
fw:RegisterEvent("PLAYER_LOGIN")
fw:RegisterEvent("QUEST_LOG_UPDATE")
fw:SetScript("OnEvent", function()
  if not AttachForeverUI() and WorldMapFrame and not fw.hooked then
    fw.hooked = true
    WorldMapFrame:HookScript("OnShow", AttachForeverUI)
  end
  FUIUpdate()
end)
