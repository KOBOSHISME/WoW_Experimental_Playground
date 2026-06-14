local _, WEP = ...

WEP.Tools = WEP.Tools or {}

local List = {}
WEP.Tools.List = List

WEP:Log("List", "loaded")

local DEFAULT_ROW_HEIGHT = 24
local DEFAULT_WIDTH = 360
local DEFAULT_VISIBLE_ROWS = 8
local COLUMN_GAP = 8

local function setSolidColor(texture, red, green, blue, alpha)
	if texture.SetColorTexture then
		texture:SetColorTexture(red, green, blue, alpha)
	else
		texture:SetTexture(red, green, blue, alpha)
	end
end

local function ensureRow(list, index)
	if list.rows[index] then
		return list.rows[index]
	end

	local row = CreateFrame("Button", nil, list.frame)
	row:SetHeight(list.rowHeight)
	row:SetPoint("LEFT", list.frame, "LEFT", 0, 0)
	row:SetPoint("RIGHT", list.frame, "RIGHT", 0, 0)

	row.background = row:CreateTexture(nil, "BACKGROUND")
	row.background:SetAllPoints(row)
	setSolidColor(row.background, 0, 0, 0, 0)

	row.columns = {}

	for columnIndex, column in ipairs(list.columns) do
		local text = row:CreateFontString(nil, "ARTWORK", column.font or "GameFontHighlightSmall")
		text:SetJustifyH(column.justifyH or "LEFT")
		text:SetJustifyV("MIDDLE")
		text:SetHeight(list.rowHeight)

		if columnIndex == 1 then
			text:SetPoint("LEFT", row, "LEFT", 6, 0)
		else
			text:SetPoint("LEFT", row.columns[columnIndex - 1], "RIGHT", COLUMN_GAP, 0)
		end

		text:SetWidth(column.width or 100)
		row.columns[columnIndex] = text
	end

	list.rows[index] = row
	return row
end

function List.Create(parent, config)
	config = config or {}

	local frame = CreateFrame("Frame", nil, parent)
	local width = config.width or DEFAULT_WIDTH
	local rowHeight = config.rowHeight or DEFAULT_ROW_HEIGHT
	local visibleRows = config.visibleRows or DEFAULT_VISIBLE_ROWS

	frame:SetSize(width, rowHeight * visibleRows)

	local list = {
		frame = frame,
		rows = {},
		columns = config.columns or {},
		rowHeight = rowHeight,
		visibleRows = visibleRows,
		emptyText = config.emptyText or "No items.",
	}

	frame.empty = frame:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	frame.empty:SetPoint("CENTER", frame, "CENTER", 0, 0)
	frame.empty:SetJustifyH("CENTER")
	frame.empty:SetText(list.emptyText)

	frame.more = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	frame.more:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 2)
	frame.more:SetJustifyH("RIGHT")
	frame.more:Hide()

	function list:SetItems(items)
		items = items or {}
		local visibleCount = math.min(#items, self.visibleRows)

		if self.lastLoggedCount ~= #items or self.lastLoggedVisibleCount ~= visibleCount then
			self.lastLoggedCount = #items
			self.lastLoggedVisibleCount = visibleCount
			WEP:Log("List", "items_set", {
				count = #items,
				visible = visibleCount,
			})
		end

		for index = 1, visibleCount do
			local item = items[index]
			local row = ensureRow(self, index)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -((index - 1) * self.rowHeight))
			row:SetPoint("RIGHT", self.frame, "RIGHT", 0, 0)

			local red, green, blue, alpha = 0, 0, 0, index % 2 == 0 and 0.14 or 0.05
			if item.color then
				red = item.color.r or red
				green = item.color.g or green
				blue = item.color.b or blue
				alpha = item.color.a or alpha
			end

			setSolidColor(row.background, red, green, blue, alpha)

			local values = item.columns or item
			for columnIndex, column in ipairs(self.columns) do
				local value = values[column.key or columnIndex]
				row.columns[columnIndex]:SetText(value ~= nil and tostring(value) or "")
			end

			if type(item.onClick) == "function" then
				row:SetScript("OnClick", function()
					item.onClick(item)
				end)
			else
				row:SetScript("OnClick", nil)
			end

			row:Show()
		end

		for index = visibleCount + 1, #self.rows do
			self.rows[index]:Hide()
		end

		if #items == 0 then
			self.frame.empty:SetText(self.emptyText)
			self.frame.empty:Show()
		else
			self.frame.empty:Hide()
		end

		if #items > visibleCount then
			self.frame.more:SetText("+" .. (#items - visibleCount) .. " more")
			self.frame.more:Show()
		else
			self.frame.more:Hide()
		end
	end

	function list:SetVisibleRows(visibleRows)
		visibleRows = math.max(1, math.floor(tonumber(visibleRows) or self.visibleRows))

		if visibleRows == self.visibleRows then
			return
		end

		self.visibleRows = visibleRows
		self.frame:SetHeight(self.rowHeight * self.visibleRows)
		WEP:Log("List", "visible_rows_set", {
			visibleRows = self.visibleRows,
		})
	end

	function list:SetEmptyText(text)
		self.emptyText = text or ""
		self.frame.empty:SetText(self.emptyText)
		WEP:Log("List", "empty_text_set", {
			text = self.emptyText,
		})
	end

	WEP:Log("List", "created", {
		columns = #list.columns,
		visibleRows = visibleRows,
		width = width,
	})
	return list
end
