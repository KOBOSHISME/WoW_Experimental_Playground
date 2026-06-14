local _, WEP = ...

local FeaturePanel = {}
WEP.FeaturePanel = FeaturePanel

local WindowTool = WEP.Tools.Window

WEP:Log("FeaturePanel", "loaded")

local ROW_HEIGHT = 48

local panelWindow

local function setButtonEnabled(button, enabled)
	if not button then
		return
	end

	if enabled == false then
		if button.Disable then
			button:Disable()
		end

		if button.SetAlpha then
			button:SetAlpha(0.45)
		end
	else
		if button.Enable then
			button:Enable()
		end

		if button.SetAlpha then
			button:SetAlpha(1)
		end
	end
end

local function setSolidColor(texture, red, green, blue, alpha)
	if texture.SetColorTexture then
		texture:SetColorTexture(red, green, blue, alpha)
	else
		texture:SetTexture(red, green, blue, alpha)
	end
end

local function getCheckedValue(checkButton)
	local checked = checkButton:GetChecked()
	return checked == true or checked == 1
end

local function ensureRow(window, index)
	window.rows = window.rows or {}

	if window.rows[index] then
		return window.rows[index]
	end

	local row = CreateFrame("Frame", nil, window.rowsFrame)
	row:SetSize(392, ROW_HEIGHT)

	row.background = row:CreateTexture(nil, "BACKGROUND")
	row.background:SetAllPoints(row)

	row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	row.check:SetPoint("LEFT", row, "LEFT", -4, 0)

	row.title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.title:SetPoint("LEFT", row.check, "RIGHT", 2, 8)
	row.title:SetWidth(280)
	row.title:SetJustifyH("LEFT")

	row.description = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.description:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
	row.description:SetWidth(280)
	row.description:SetJustifyH("LEFT")

	row.openButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.openButton:SetSize(64, 22)
	row.openButton:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	row.openButton:SetText("Open")

	row.status = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.status:SetPoint("RIGHT", row.openButton, "LEFT", -8, 0)
	row.status:SetWidth(52)
	row.status:SetJustifyH("RIGHT")

	row.check:SetScript("OnClick", function(button)
		if not row.featureId then
			return
		end

		WEP:Log("FeaturePanel", "feature_toggle_clicked", {
			id = row.featureId,
			enabled = getCheckedValue(button),
		})
		local ok, err = WEP:SetFeatureEnabled(row.featureId, getCheckedValue(button))
		if not ok then
			WEP:Log("FeaturePanel", "feature_toggle_failed", {
				id = row.featureId,
				error = err,
			}, "error")
			WEP:Print("Feature toggle failed:", err)
		end

		FeaturePanel:RefreshWindow()
	end)

	row.openButton:SetScript("OnClick", function()
		if not row.featureId then
			return
		end

		WEP:Log("FeaturePanel", "feature_open_clicked", {
			id = row.featureId,
		})
		local ok, err = WEP:OpenFeatureUI(row.featureId)
		if not ok then
			WEP:Log("FeaturePanel", "feature_open_failed", {
				id = row.featureId,
				error = err,
			}, "error")
			WEP:Print("Feature UI unavailable:", err)
		end

		FeaturePanel:RefreshWindow()
	end)

	window.rows[index] = row
	return row
end

function FeaturePanel:EnsureWindow()
	if panelWindow then
		return panelWindow
	end

	if not WindowTool then
		WEP:Log("FeaturePanel", "window_unavailable", nil, "error")
		WEP:Print("Feature panel UI tools are unavailable.")
		return nil
	end

	local window, err = WindowTool.Create({
		name = "WEPFeaturePanelWindow",
		title = "WEP Features",
		width = 500,
		height = 320,
		onShow = function()
			self:RefreshWindow()
		end,
	})

	if not window then
		WEP:Log("FeaturePanel", "window_failed", {
			error = err,
		}, "error")
		WEP:Print("Feature panel failed:", err)
		return nil
	end

	local content = window.content

	window.summaryText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	window.summaryText:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
	window.summaryText:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
	window.summaryText:SetJustifyH("LEFT")

	window.rowsFrame = CreateFrame("Frame", nil, content)
	window.rowsFrame:SetPoint("TOPLEFT", window.summaryText, "BOTTOMLEFT", 0, -12)
	window.rowsFrame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
	window.rowsFrame:SetHeight(ROW_HEIGHT * 4)

	window.emptyText = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	window.emptyText:SetPoint("CENTER", content, "CENTER", 0, 0)
	window.emptyText:SetText("No registered features.")
	window.emptyText:Hide()

	panelWindow = window
	WEP:Log("FeaturePanel", "window_created")
	return panelWindow
end

function FeaturePanel:RefreshWindow()
	local window = panelWindow
	if not window or not window:IsShown() then
		return
	end

	local features = WEP:GetFeatures()
	local activeCount = 0

	for _, feature in ipairs(features) do
		if feature.enabled then
			activeCount = activeCount + 1
		end
	end

	window.summaryText:SetText("Active features: " .. activeCount .. "/" .. #features)
	WEP:Log("FeaturePanel", "refreshed", {
		active = activeCount,
		total = #features,
	})

	for index, feature in ipairs(features) do
		local row = ensureRow(window, index)
		row.featureId = feature.id
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", window.rowsFrame, "TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
		row:SetPoint("RIGHT", window.rowsFrame, "RIGHT", 0, 0)

		setSolidColor(row.background, 0, 0, 0, index % 2 == 0 and 0.14 or 0.06)
		row.check:SetChecked(feature.enabled == true)
		row.title:SetText(feature.title)
		row.description:SetText(feature.description)
		row.status:SetText(feature.enabled and "On" or "Off")
		row.status:SetTextColor(feature.enabled and 0.3 or 0.8, feature.enabled and 1 or 0.3, 0.3)

		row.status:ClearAllPoints()
		if feature.hasUI then
			row.status:SetPoint("RIGHT", row.openButton, "LEFT", -8, 0)
			row.openButton:Show()
			setButtonEnabled(row.openButton, feature.enabled == true)
		else
			row.status:SetPoint("RIGHT", row, "RIGHT", -8, 0)
			row.openButton:Hide()
		end

		row:Show()
	end

	for index = #features + 1, #(window.rows or {}) do
		window.rows[index]:Hide()
	end

	if #features == 0 then
		window.emptyText:Show()
	else
		window.emptyText:Hide()
	end
end

function FeaturePanel:ShowWindow()
	local window = self:EnsureWindow()
	if not window then
		return
	end

	window:Show()
	WEP:Log("FeaturePanel", "shown")
	self:RefreshWindow()
end
