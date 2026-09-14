local ADDON_NAME = ...

local TaskMinder = CreateFrame("Frame")
_G.TaskMinder = TaskMinder

local DAILY = "DAILY"
local WEEKLY = "WEEKLY"
local MAIN_WINDOW_MIN_WIDTH = 260
local MAIN_WINDOW_MIN_HEIGHT = 120
local MAIN_WINDOW_MAX_WIDTH = 700
local MAIN_WINDOW_MAX_HEIGHT = 800
local VALID_FREQUENCIES = {
    [DAILY] = true,
    [WEEKLY] = true,
}

-- Shared visual language for TaskMinder and future Minder addons. All colors use
-- native WoW's WHITE8X8 texture; no external artwork or UI assets are required.
local Theme = {
    texture = "Interface\\Buttons\\WHITE8X8",
    borderWidth = 1,
    spacing = {
        tiny = 4,
        small = 8,
        medium = 12,
        large = 16,
        windowInset = 14,
    },
    rowHeights = {
        checklist = 30,
        manage = 34,
    },
    fonts = {
        title = "SystemFont_Med1",
        body = "SystemFont_Small",
        small = "SystemFont_Small",
        button = "SystemFont_Small",
    },
    colors = {
        background = { 0.025, 0.031, 0.043, 0.96 },
        surface = { 0.055, 0.067, 0.086, 0.98 },
        row = { 0.071, 0.084, 0.106, 0.98 },
        rowHover = { 0.093, 0.112, 0.137, 1.0 },
        border = { 0.20, 0.24, 0.29, 0.9 },
        accent = { 0.22, 0.78, 0.73, 1.0 },
        accentMuted = { 0.16, 0.52, 0.50, 1.0 },
        text = { 0.90, 0.93, 0.95, 1.0 },
        muted = { 0.52, 0.58, 0.65, 1.0 },
        completed = { 0.39, 0.44, 0.50, 1.0 },
        danger = { 0.82, 0.37, 0.38, 1.0 },
    },
}
TaskMinder.Theme = Theme

-- Keep the addon accent in step with the current character without changing
-- the neutral surfaces shared by the Minder UI.
local function applyClassAccentColor()
    local _, classFile = UnitClass("player")
    local classColor = classFile and RAID_CLASS_COLORS[classFile]
    if not classColor then
        return
    end

    Theme.colors.accent = { classColor.r, classColor.g, classColor.b, 1.0 }
    Theme.colors.accentMuted = {
        classColor.r * 0.68,
        classColor.g * 0.68,
        classColor.b * 0.68,
        1.0,
    }
end

local function setTextColor(fontString, color)
    fontString:SetTextColor(color[1], color[2], color[3], color[4])
end

local function getThemeFont(name)
    return _G[Theme.fonts[name]]
end

local function addBorder(frame, color)
    local border = {}
    local thickness = Theme.borderWidth
    local points = {
        { "TOPLEFT", "TOPRIGHT", 0, 0, thickness },
        { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 0, thickness },
        { "TOPLEFT", "BOTTOMLEFT", 0, 0, thickness },
        { "TOPRIGHT", "BOTTOMRIGHT", 0, 0, thickness },
    }

    for index, point in ipairs(points) do
        local line = frame:CreateTexture(nil, "BORDER")
        line:SetColorTexture(color[1], color[2], color[3], color[4])
        if index <= 2 then
            line:SetPoint(point[1], frame, point[1], point[3], point[4])
            line:SetPoint(point[2], frame, point[2], point[3], point[4])
            line:SetHeight(point[5])
        else
            line:SetPoint(point[1], frame, point[1], point[3], point[4])
            line:SetPoint(point[2], frame, point[2], point[3], point[4])
            line:SetWidth(point[5])
        end
        border[index] = line
    end
    return border
end

local function applyPanelStyle(frame)
    frame:SetBackdrop({
        bgFile = Theme.texture,
        edgeFile = Theme.texture,
        tile = true,
        tileSize = 8,
        edgeSize = Theme.borderWidth,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    frame:SetBackdropColor(unpack(Theme.colors.background))
    frame:SetBackdropBorderColor(unpack(Theme.colors.border))
end

local function addTitleAccent(frame)
    local accent = frame:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", Theme.spacing.windowInset, -36)
    accent:SetPoint("TOPRIGHT", -Theme.spacing.windowInset, -36)
    accent:SetHeight(1)
    accent:SetColorTexture(unpack(Theme.colors.accentMuted))
    return accent
end

local function styleFlatButton(button, tone)
    button:SetNormalFontObject(getThemeFont("button"))
    button:SetHighlightFontObject(getThemeFont("button"))
    button:SetDisabledFontObject(getThemeFont("button"))
    for _, segment in ipairs({ button.Left, button.Middle, button.Right }) do
        if segment then
            segment:Hide()
        end
    end
    if button:GetFontString() then
        setTextColor(button:GetFontString(), Theme.colors.text)
    end

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(unpack(Theme.colors.surface))
    button.tmBackground = background
    button.tmBorder = addBorder(button, tone == "danger" and Theme.colors.danger or Theme.colors.border)
    button:HookScript("OnEnter", function(self)
        if self:IsEnabled() then
            self.tmBackground:SetColorTexture(unpack(Theme.colors.rowHover))
        end
    end)
    button:HookScript("OnLeave", function(self)
        self.tmBackground:SetColorTexture(unpack(Theme.colors.surface))
    end)
end

local function createTitleBarIconPart(parent, width, height, point, xOffset, yOffset, color)
    local part = parent:CreateTexture(nil, "ARTWORK")
    part:SetSize(width, height)
    part:SetPoint(point, parent, point, xOffset or 0, yOffset or 0)
    part:SetColorTexture(unpack(color))
    return part
end

local function styleTitleBarIcon(button, iconType)
    local icon = CreateFrame("Frame", nil, button)
    icon:SetSize(16, 16)
    icon:SetPoint("CENTER")
    icon.tintParts = {}

    function icon:SetTint(color)
        for _, part in ipairs(self.tintParts) do
            part:SetColorTexture(unpack(color))
        end
    end

    if iconType == "gear" then
        -- A compact cog assembled from the shared UI texture keeps the icon
        -- crisp without relying on client-specific texture atlas names.
        table.insert(icon.tintParts, createTitleBarIconPart(icon, 8, 8, "CENTER", 0, 0, Theme.colors.accentMuted))
        table.insert(icon.tintParts, createTitleBarIconPart(icon, 4, 3, "TOP", 0, 1, Theme.colors.accentMuted))
        table.insert(icon.tintParts, createTitleBarIconPart(icon, 4, 3, "BOTTOM", 0, -1, Theme.colors.accentMuted))
        table.insert(icon.tintParts, createTitleBarIconPart(icon, 3, 4, "LEFT", 1, 0, Theme.colors.accentMuted))
        table.insert(icon.tintParts, createTitleBarIconPart(icon, 3, 4, "RIGHT", -1, 0, Theme.colors.accentMuted))
        createTitleBarIconPart(icon, 4, 4, "CENTER", 0, 0, Theme.colors.surface)
    else
        local shackleTop = createTitleBarIconPart(icon, 8, 2, "TOP", 0, 0, Theme.colors.accentMuted)
        local shackleLeft = createTitleBarIconPart(icon, 2, 6, "TOPLEFT", 2, -1, Theme.colors.accentMuted)
        local shackleRight = createTitleBarIconPart(icon, 2, 6, "TOPRIGHT", -2, -1, Theme.colors.accentMuted)
        table.insert(icon.tintParts, shackleTop)
        table.insert(icon.tintParts, shackleLeft)
        table.insert(icon.tintParts, shackleRight)
        table.insert(icon.tintParts, createTitleBarIconPart(icon, 12, 8, "BOTTOM", 0, 0, Theme.colors.accentMuted))
        createTitleBarIconPart(icon, 2, 3, "BOTTOM", 0, 2, Theme.colors.surface)

        function icon:SetLocked(isLocked)
            shackleTop:ClearAllPoints()
            shackleLeft:ClearAllPoints()
            if isLocked then
                shackleTop:SetPoint("TOP", self, "TOP", 0, 0)
                shackleLeft:SetPoint("TOPLEFT", self, "TOPLEFT", 2, -1)
                shackleRight:Show()
            else
                shackleTop:SetPoint("TOP", self, "TOP", 3, 0)
                shackleLeft:SetPoint("TOPLEFT", self, "TOPLEFT", 5, -1)
                shackleRight:Hide()
            end
        end
    end

    button.tmIcon = icon
    button:HookScript("OnEnter", function(self)
        self.tmIcon:SetTint(Theme.colors.accent)
    end)
    button:HookScript("OnLeave", function(self)
        self.tmIcon:SetTint(Theme.colors.accentMuted)
    end)
end

local function styleRow(row)
    local background = row:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(unpack(Theme.colors.row))
    row.tmBackground = background
    row.tmBaseColor = Theme.colors.row
    row.tmBorder = addBorder(row, Theme.colors.border)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        self.tmBackground:SetColorTexture(unpack(Theme.colors.rowHover))
    end)
    row:SetScript("OnLeave", function(self)
        self.tmBackground:SetColorTexture(unpack(self.tmBaseColor))
    end)
end

local function styleScrollArea(frame)
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(unpack(Theme.colors.surface))
    frame.tmBackground = background
    frame.tmBorder = addBorder(frame, Theme.colors.border)
end

local function styleInput(input)
    input:SetBackdrop({
        bgFile = Theme.texture,
        edgeFile = Theme.texture,
        edgeSize = Theme.borderWidth,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    input:SetBackdropColor(unpack(Theme.colors.surface))
    input:SetBackdropBorderColor(unpack(Theme.colors.border))
    input:SetTextInsets(Theme.spacing.small, Theme.spacing.small, 0, 0)
    input:HookScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(unpack(Theme.colors.accent))
    end)
    input:HookScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(unpack(Theme.colors.border))
    end)
end

local function isValidName(name)
    return type(name) == "string" and name:match("%S") ~= nil
end

local function isValidFrequency(frequency)
    return VALID_FREQUENCIES[frequency] == true
end

local function initializeDatabase()
    if type(TaskMinderDB) ~= "table" then
        TaskMinderDB = {}
    end

    if type(TaskMinderDB.tasks) ~= "table" then
        TaskMinderDB.tasks = {}
    end

    if type(TaskMinderDB.nextTaskNumber) ~= "number" then
        TaskMinderDB.nextTaskNumber = 1
    end

    if type(TaskMinderDB.isWindowLocked) ~= "boolean" then
        TaskMinderDB.isWindowLocked = false
    end

    if type(TaskMinderDB.isMainWindowShown) ~= "boolean" then
        TaskMinderDB.isMainWindowShown = true
    end

    if type(TaskMinderDB.minimapAngle) ~= "number" then
        TaskMinderDB.minimapAngle = 225
    end
end

local function getTask(taskID)
    return TaskMinderDB.tasks[taskID]
end

local function getNextResetTimestamp(frequency, now)
    local secondsUntilReset

    if frequency == DAILY then
        secondsUntilReset = GetQuestResetTime()
    elseif frequency == WEEKLY and C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
        secondsUntilReset = C_DateAndTime.GetSecondsUntilWeeklyReset()
    end

    if type(secondsUntilReset) ~= "number" then
        return nil, "Unable to determine the next reset time."
    end

    return now + secondsUntilReset
end

local function rebuildNextPendingResetTimestamp()
    local nextResetTimestamp

    for _, task in pairs(TaskMinderDB.tasks) do
        if task.completed and type(task.nextResetTimestamp) == "number"
            and (not nextResetTimestamp or task.nextResetTimestamp < nextResetTimestamp) then
            nextResetTimestamp = task.nextResetTimestamp
        end
    end

    TaskMinder.nextPendingResetTimestamp = nextResetTimestamp
    return nextResetTimestamp
end

local function reactivateExpiredTasks()
    local now = GetServerTime()

    if TaskMinder.nextPendingResetTimestamp and TaskMinder.nextPendingResetTimestamp > now then
        return false
    end

    local changed = false
    local nextResetTimestamp
    for _, task in pairs(TaskMinderDB.tasks) do
        if task.completed and type(task.nextResetTimestamp) == "number" then
            if task.nextResetTimestamp <= now then
                task.completed = false
                task.completedTimestamp = nil
                task.nextResetTimestamp = nil
                changed = true
            elseif not nextResetTimestamp or task.nextResetTimestamp < nextResetTimestamp then
                nextResetTimestamp = task.nextResetTimestamp
            end
        end
    end

    TaskMinder.nextPendingResetTimestamp = nextResetTimestamp
    return changed
end

local function refreshWindows()
    if TaskMinder.RefreshMainWindow then
        TaskMinder:RefreshMainWindow()
    end
    if TaskMinder.RefreshManageWindow then
        TaskMinder:RefreshManageWindow()
    end
end

function TaskMinder:GetTasks()
    return TaskMinderDB.tasks
end

function TaskMinder:GetTask(taskID)
    return getTask(taskID)
end

function TaskMinder:RefreshExpiredTasks()
    local changed = reactivateExpiredTasks()
    if changed then
        refreshWindows()
    end
    return changed
end

function TaskMinder:CreateTask(name, frequency)
    if not isValidName(name) then
        return nil, "A task name is required."
    end

    if not isValidFrequency(frequency) then
        return nil, "Frequency must be DAILY or WEEKLY."
    end

    local now = GetServerTime()
    local taskID = string.format("task-%d-%d", now, TaskMinderDB.nextTaskNumber)
    TaskMinderDB.nextTaskNumber = TaskMinderDB.nextTaskNumber + 1

    local task = {
        id = taskID,
        name = name,
        frequency = frequency,
        completed = false,
        completedTimestamp = nil,
        nextResetTimestamp = nil,
        createdTimestamp = now,
    }

    TaskMinderDB.tasks[taskID] = task
    refreshWindows()
    return task
end

function TaskMinder:UpdateTask(taskID, changes)
    local task = getTask(taskID)
    if not task then
        return nil, "Task not found."
    end

    if type(changes) ~= "table" then
        return nil, "Changes must be a table."
    end

    if changes.name ~= nil then
        if not isValidName(changes.name) then
            return nil, "A task name is required."
        end
        task.name = changes.name
    end

    local frequencyChanged = changes.frequency ~= nil and changes.frequency ~= task.frequency
    if changes.frequency ~= nil then
        if not isValidFrequency(changes.frequency) then
            return nil, "Frequency must be DAILY or WEEKLY."
        end
        task.frequency = changes.frequency
    end

    if frequencyChanged and task.completed then
        local wasNextReset = task.nextResetTimestamp
        task.completed = false
        task.completedTimestamp = nil
        task.nextResetTimestamp = nil
        if wasNextReset == TaskMinder.nextPendingResetTimestamp then
            rebuildNextPendingResetTimestamp()
        end
    end

    refreshWindows()
    return task
end

function TaskMinder:DeleteTask(taskID)
    local task = getTask(taskID)
    if not task then
        return nil, "Task not found."
    end

    TaskMinderDB.tasks[taskID] = nil
    if task.completed and task.nextResetTimestamp == TaskMinder.nextPendingResetTimestamp then
        rebuildNextPendingResetTimestamp()
    end
    refreshWindows()
    return true
end

function TaskMinder:CompleteTask(taskID)
    local task = getTask(taskID)
    if not task then
        return nil, "Task not found."
    end

    local now = GetServerTime()
    local resetTimestamp, errorMessage = getNextResetTimestamp(task.frequency, now)
    if not resetTimestamp then
        return nil, errorMessage
    end

    task.completed = true
    task.completedTimestamp = now
    task.nextResetTimestamp = resetTimestamp
    rebuildNextPendingResetTimestamp()
    refreshWindows()
    return task
end

function TaskMinder:ReactivateTask(taskID)
    local task = getTask(taskID)
    if not task then
        return nil, "Task not found."
    end

    local wasCompleted = task.completed
    local wasNextReset = task.nextResetTimestamp
    task.completed = false
    task.completedTimestamp = nil
    task.nextResetTimestamp = nil
    if wasCompleted and wasNextReset == TaskMinder.nextPendingResetTimestamp then
        rebuildNextPendingResetTimestamp()
    end
    refreshWindows()
    return task
end

local function getActiveTasks()
    local activeTasks = {}

    for _, task in pairs(TaskMinderDB.tasks) do
        if not task.completed then
            table.insert(activeTasks, task)
        end
    end

    table.sort(activeTasks, function(left, right)
        if left.createdTimestamp == right.createdTimestamp then
            return left.id < right.id
        end
        return left.createdTimestamp < right.createdTimestamp
    end)

    return activeTasks
end

local function getTaskListSignature(tasks)
    local parts = {}

    for index, task in ipairs(tasks) do
        parts[index] = table.concat({ task.id, task.name, task.frequency }, "\031")
    end

    return table.concat(parts, "\030")
end

local function saveWindowPosition(frame)
    local point, _, relativePoint, xOffset, yOffset = frame:GetPoint(1)
    TaskMinderDB.windowPosition = {
        point = point,
        relativePoint = relativePoint,
        xOffset = xOffset,
        yOffset = yOffset,
        width = frame:GetWidth(),
        height = frame:GetHeight(),
    }
end

local function restoreWindowPosition(frame)
    local position = TaskMinderDB.windowPosition
    frame:ClearAllPoints()

    local width = type(position) == "table" and position.width or 440
    local height = type(position) == "table" and position.height or 420
    width = math.min(math.max(width, MAIN_WINDOW_MIN_WIDTH), MAIN_WINDOW_MAX_WIDTH)
    height = math.min(math.max(height, MAIN_WINDOW_MIN_HEIGHT), MAIN_WINDOW_MAX_HEIGHT)
    frame:SetSize(width, height)

    if type(position) == "table" and position.point and position.relativePoint then
        frame:SetPoint(position.point, UIParent, position.relativePoint, position.xOffset, position.yOffset)
    else
        frame:SetPoint("CENTER")
    end
end

local function createMainWindow()
    if TaskMinder.MainFrame then
        return TaskMinder.MainFrame
    end

    local frame = CreateFrame("Frame", "TaskMinderMainFrame", UIParent, "BackdropTemplate")
    frame:SetSize(440, 420)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(MAIN_WINDOW_MIN_WIDTH, MAIN_WINDOW_MIN_HEIGHT, MAIN_WINDOW_MAX_WIDTH, MAIN_WINDOW_MAX_HEIGHT)
    frame:EnableMouse(true)
    applyPanelStyle(frame)
    frame:Hide()
    restoreWindowPosition(frame)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", 22, -18)
    title:SetFontObject(getThemeFont("title"))
    setTextColor(title, Theme.colors.text)
    title:SetText("TaskMinder")
    addTitleAccent(frame)

    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", 16, -12)
    titleBar:SetPoint("TOPRIGHT", -122, -12)
    titleBar:SetHeight(32)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function()
        if not TaskMinderDB.isWindowLocked then
            frame:StartMoving()
        end
    end)
    titleBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        saveWindowPosition(frame)
    end)

    local resizeGrip
    local closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeButton:SetSize(28, 22)
    closeButton:SetPoint("TOPRIGHT", -22, -16)
    closeButton:SetText("X")
    styleFlatButton(closeButton, "danger")
    closeButton:SetScript("OnClick", function()
        TaskMinderDB.isMainWindowShown = false
        frame:Hide()
    end)

    local lockButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    lockButton:SetSize(28, 22)
    lockButton:SetPoint("RIGHT", closeButton, "LEFT", -4, 0)
    lockButton:SetText("")
    styleFlatButton(lockButton)
    styleTitleBarIcon(lockButton, "lock")

    local gearButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    gearButton:SetSize(28, 22)
    gearButton:SetPoint("RIGHT", lockButton, "LEFT", -4, 0)
    gearButton:SetText("")
    styleFlatButton(gearButton)
    styleTitleBarIcon(gearButton, "gear")
    gearButton:SetScript("OnClick", function()
        TaskMinder:ToggleManageWindow()
    end)

    local function updateLockButton()
        lockButton.tmIcon:SetLocked(TaskMinderDB.isWindowLocked)
        if TaskMinderDB.isWindowLocked then
            resizeGrip:Hide()
        else
            resizeGrip:Show()
        end
    end

    lockButton:SetScript("OnClick", function()
        TaskMinderDB.isWindowLocked = not TaskMinderDB.isWindowLocked
        updateLockButton()
    end)
    lockButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(TaskMinderDB.isWindowLocked and "Unlock window" or "Lock window")
        GameTooltip:Show()
    end)
    lockButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local listFrame = CreateFrame("Frame", nil, frame)
    listFrame:SetPoint("TOPLEFT", 20, -54)
    listFrame:SetPoint("BOTTOMRIGHT", -20, 20)
    styleScrollArea(listFrame)

    local scrollFrame = CreateFrame("ScrollFrame", nil, listFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(1, 1)
    scrollFrame:SetScrollChild(scrollChild)

    local emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("TOP", scrollChild, "TOP", 0, -62)
    emptyText:SetWidth(340)
    emptyText:SetJustifyH("CENTER")
    emptyText:SetFontObject(getThemeFont("body"))
    setTextColor(emptyText, Theme.colors.muted)
    emptyText:SetText("No active tasks. Add tasks from the gear menu.")

    frame.lockButton = lockButton
    frame.scrollFrame = scrollFrame
    frame.scrollChild = scrollChild
    frame.emptyText = emptyText
    frame.rows = {}
    frame.lastTaskListSignature = nil
    TaskMinder.MainFrame = frame

    resizeGrip = CreateFrame("Button", nil, frame)
    resizeGrip:SetSize(20, 20)
    resizeGrip:SetPoint("BOTTOMRIGHT", -4, 4)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:RegisterForDrag("LeftButton")
    resizeGrip:SetScript("OnDragStart", function()
        if not TaskMinderDB.isWindowLocked then
            frame:StartSizing("BOTTOMRIGHT")
        end
    end)
    resizeGrip:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        saveWindowPosition(frame)
    end)
    resizeGrip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText("Resize window")
        GameTooltip:Show()
    end)
    resizeGrip:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    frame.resizeGrip = resizeGrip

    frame:SetScript("OnSizeChanged", function(self)
        local contentWidth = math.max(self.scrollFrame:GetWidth(), 1)
        self.scrollChild:SetWidth(contentWidth)
        self.emptyText:SetWidth(math.max(contentWidth - 20, 1))
    end)
    local contentWidth = math.max(frame.scrollFrame:GetWidth(), 1)
    frame.scrollChild:SetWidth(contentWidth)
    frame.emptyText:SetWidth(math.max(contentWidth - 20, 1))
    updateLockButton()
    saveWindowPosition(frame)

    frame:SetScript("OnShow", function()
        TaskMinder:RefreshExpiredTasks()
        TaskMinder:RefreshMainWindow()
    end)

    return frame
end

local function createTaskRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(Theme.rowHeights.checklist)
    row:SetPoint("TOPLEFT", 0, -((index - 1) * (Theme.rowHeights.checklist + Theme.spacing.tiny)))
    row:SetPoint("TOPRIGHT", 0, -((index - 1) * (Theme.rowHeights.checklist + Theme.spacing.tiny)))
    styleRow(row)

    local checkbox = CreateFrame("CheckButton", nil, row)
    checkbox:SetSize(18, 18)
    checkbox:SetPoint("LEFT", Theme.spacing.small, 0)
    local checkBackground = checkbox:CreateTexture(nil, "BACKGROUND")
    checkBackground:SetAllPoints()
    checkBackground:SetColorTexture(unpack(Theme.colors.background))
    checkbox.tmBackground = checkBackground
    checkbox.tmBorder = addBorder(checkbox, Theme.colors.accentMuted)
    checkbox:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    checkbox:GetCheckedTexture():SetVertexColor(unpack(Theme.colors.accent))
    checkbox:HookScript("OnEnter", function(self)
        for _, line in ipairs(self.tmBorder) do
            line:SetColorTexture(unpack(Theme.colors.accent))
        end
    end)
    checkbox:HookScript("OnLeave", function(self)
        for _, line in ipairs(self.tmBorder) do
            line:SetColorTexture(unpack(Theme.colors.accentMuted))
        end
    end)
    checkbox:SetScript("OnClick", function(self)
        local task, errorMessage = TaskMinder:CompleteTask(self.taskID)
        if not task then
            self:SetChecked(false)
            print("TaskMinder: " .. errorMessage)
        end
    end)

    local frequency = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frequency:SetPoint("RIGHT", -Theme.spacing.small, 0)
    frequency:SetJustifyH("RIGHT")
    frequency:SetFontObject(getThemeFont("small"))
    setTextColor(frequency, Theme.colors.accentMuted)

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    name:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
    name:SetPoint("RIGHT", frequency, "LEFT", -8, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    name:SetFontObject(getThemeFont("body"))
    setTextColor(name, Theme.colors.text)

    row.checkbox = checkbox
    row.name = name
    row.frequency = frequency
    return row
end

function TaskMinder:RefreshMainWindow()
    local frame = self.MainFrame
    if not frame or not frame:IsShown() then
        return
    end

    local activeTasks = getActiveTasks()
    local signature = getTaskListSignature(activeTasks)
    if signature == frame.lastTaskListSignature then
        return
    end

    frame.lastTaskListSignature = signature
    if #activeTasks == 0 then
        frame.emptyText:Show()
    else
        frame.emptyText:Hide()
    end

    for index, task in ipairs(activeTasks) do
        local row = frame.rows[index]
        if not row then
            row = createTaskRow(frame.scrollChild, index)
            frame.rows[index] = row
        end

        row.checkbox.taskID = task.id
        row.checkbox:SetChecked(false)
        row.name:SetText(task.name)
        row.frequency:SetText(task.frequency == DAILY and "Daily" or "Weekly")
        row:Show()
    end

    for index = #activeTasks + 1, #frame.rows do
        frame.rows[index]:Hide()
    end

    local contentHeight = math.max(#activeTasks * (Theme.rowHeights.checklist + Theme.spacing.tiny), 1)
    frame.scrollChild:SetHeight(contentHeight)
    frame.scrollFrame:SetVerticalScroll(0)
end

function TaskMinder:ToggleMainWindow()
    local frame = createMainWindow()
    if frame:IsShown() then
        TaskMinderDB.isMainWindowShown = false
        frame:Hide()
    else
        TaskMinderDB.isMainWindowShown = true
        frame:Show()
    end
end

local function getAllTasks()
    local tasks = {}

    for _, task in pairs(TaskMinderDB.tasks) do
        table.insert(tasks, task)
    end

    table.sort(tasks, function(left, right)
        if left.createdTimestamp == right.createdTimestamp then
            return left.id < right.id
        end
        return left.createdTimestamp < right.createdTimestamp
    end)

    return tasks
end

local function getManageListSignature(tasks)
    local parts = {}

    for index, task in ipairs(tasks) do
        parts[index] = table.concat({ task.id, task.name, task.frequency, tostring(task.completed) }, "\031")
    end

    return table.concat(parts, "\030")
end

local function createTaskForm()
    if TaskMinder.TaskForm then
        return TaskMinder.TaskForm
    end

    local form = CreateFrame("Frame", "TaskMinderTaskForm", UIParent, "BackdropTemplate")
    form:SetSize(360, 190)
    form:SetPoint("CENTER", 0, 40)
    form:SetFrameStrata("FULLSCREEN_DIALOG")
    form:EnableMouse(true)
    applyPanelStyle(form)
    form:Hide()

    local title = form:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", 20, -18)
    title:SetFontObject(getThemeFont("title"))
    setTextColor(title, Theme.colors.text)
    form.title = title
    addTitleAccent(form)

    local nameLabel = form:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", 22, -54)
    nameLabel:SetFontObject(getThemeFont("small"))
    setTextColor(nameLabel, Theme.colors.muted)
    nameLabel:SetText("Name")

    local nameInput = CreateFrame("EditBox", nil, form, "BackdropTemplate")
    nameInput:SetSize(300, 24)
    nameInput:SetPoint("TOPLEFT", 22, -72)
    nameInput:SetAutoFocus(false)
    styleInput(nameInput)
    nameInput:SetFontObject(getThemeFont("body"))
    nameInput:SetTextColor(unpack(Theme.colors.text))
    form.nameInput = nameInput

    local frequencyLabel = form:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frequencyLabel:SetPoint("TOPLEFT", 22, -108)
    frequencyLabel:SetFontObject(getThemeFont("small"))
    setTextColor(frequencyLabel, Theme.colors.muted)
    frequencyLabel:SetText("Frequency")

    local dailyButton = CreateFrame("Button", nil, form, "UIPanelButtonTemplate")
    dailyButton:SetSize(76, 22)
    dailyButton:SetPoint("TOPLEFT", 88, -102)
    dailyButton:SetText("Daily")
    styleFlatButton(dailyButton)

    local weeklyButton = CreateFrame("Button", nil, form, "UIPanelButtonTemplate")
    weeklyButton:SetSize(76, 22)
    weeklyButton:SetPoint("LEFT", dailyButton, "RIGHT", 6, 0)
    weeklyButton:SetText("Weekly")
    styleFlatButton(weeklyButton)

    local errorText = form:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
    errorText:SetPoint("TOPLEFT", 22, -132)
    errorText:SetWidth(300)
    errorText:SetJustifyH("LEFT")
    errorText:SetFontObject(getThemeFont("small"))
    setTextColor(errorText, Theme.colors.danger)
    form.errorText = errorText

    local addButton = CreateFrame("Button", nil, form, "UIPanelButtonTemplate")
    addButton:SetSize(76, 24)
    addButton:SetPoint("BOTTOMRIGHT", -104, 18)
    styleFlatButton(addButton)

    local cancelButton = CreateFrame("Button", nil, form, "UIPanelButtonTemplate")
    cancelButton:SetSize(76, 24)
    cancelButton:SetPoint("BOTTOMRIGHT", -22, 18)
    cancelButton:SetText("Cancel")
    styleFlatButton(cancelButton)
    cancelButton:SetScript("OnClick", function()
        form:Hide()
    end)

    local function updateFrequencyButtons()
        local dailySelected = form.frequency == DAILY
        local weeklySelected = form.frequency == WEEKLY
        dailyButton:SetEnabled(not dailySelected)
        weeklyButton:SetEnabled(not weeklySelected)
        dailyButton.tmBackground:SetColorTexture(unpack(dailySelected and Theme.colors.accentMuted or Theme.colors.surface))
        weeklyButton.tmBackground:SetColorTexture(unpack(weeklySelected and Theme.colors.accentMuted or Theme.colors.surface))
    end

    dailyButton:SetScript("OnClick", function()
        form.frequency = DAILY
        updateFrequencyButtons()
    end)
    weeklyButton:SetScript("OnClick", function()
        form.frequency = WEEKLY
        updateFrequencyButtons()
    end)

    addButton:SetScript("OnClick", function()
        local task, errorMessage
        if form.editTaskID then
            task, errorMessage = TaskMinder:UpdateTask(form.editTaskID, {
                name = form.nameInput:GetText(),
                frequency = form.frequency,
            })
        else
            task, errorMessage = TaskMinder:CreateTask(form.nameInput:GetText(), form.frequency)
        end

        if task then
            form:Hide()
        else
            form.errorText:SetText(errorMessage)
        end
    end)

    function form:ShowForTask(task)
        self.editTaskID = task and task.id or nil
        self.title:SetText(task and "Edit Task" or "Add Task")
        self.nameInput:SetText(task and task.name or "")
        self.frequency = task and task.frequency or DAILY
        addButton:SetText(task and "Save" or "Add")
        self.errorText:SetText("")
        updateFrequencyButtons()
        self:Show()
        self.nameInput:SetFocus()
    end

    TaskMinder.TaskForm = form
    return form
end

local function createManageTaskRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(Theme.rowHeights.manage)
    row:SetPoint("TOPLEFT", 0, -((index - 1) * (Theme.rowHeights.manage + Theme.spacing.tiny)))
    row:SetPoint("TOPRIGHT", 0, -((index - 1) * (Theme.rowHeights.manage + Theme.spacing.tiny)))
    styleRow(row)

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    name:SetPoint("LEFT", 4, 0)
    name:SetWidth(205)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    name:SetFontObject(getThemeFont("body"))

    local frequency = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frequency:SetPoint("LEFT", 215, 0)
    frequency:SetWidth(58)
    frequency:SetJustifyH("LEFT")
    frequency:SetFontObject(getThemeFont("small"))

    local status = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    status:SetPoint("LEFT", 285, 0)
    status:SetWidth(70)
    status:SetJustifyH("LEFT")
    status:SetFontObject(getThemeFont("small"))

    local editButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    editButton:SetSize(48, 22)
    editButton:SetPoint("RIGHT", -62, 0)
    editButton:SetText("Edit")
    styleFlatButton(editButton)
    editButton:SetScript("OnClick", function(self)
        local task = TaskMinder:GetTask(self.taskID)
        if task then
            createTaskForm():ShowForTask(task)
        end
    end)

    local deleteButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    deleteButton:SetSize(54, 22)
    deleteButton:SetPoint("RIGHT", -4, 0)
    deleteButton:SetText("Delete")
    styleFlatButton(deleteButton, "danger")
    deleteButton:SetScript("OnClick", function(self)
        local task = TaskMinder:GetTask(self.taskID)
        if task then
            StaticPopup_Show("TASKMINDER_CONFIRM_DELETE", task.name, nil, task.id)
        end
    end)

    row.name = name
    row.frequency = frequency
    row.status = status
    row.editButton = editButton
    row.deleteButton = deleteButton
    return row
end

local function createManageWindow()
    if TaskMinder.ManageFrame then
        return TaskMinder.ManageFrame
    end

    local frame = CreateFrame("Frame", "TaskMinderManageFrame", UIParent, "BackdropTemplate")
    frame:SetSize(570, 420)
    frame:SetPoint("CENTER", 30, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    applyPanelStyle(frame)
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", 22, -18)
    title:SetFontObject(getThemeFont("title"))
    setTextColor(title, Theme.colors.text)
    title:SetText("Manage Tasks")
    addTitleAccent(frame)

    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", 16, -12)
    titleBar:SetPoint("TOPRIGHT", -145, -12)
    titleBar:SetHeight(32)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    titleBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
    end)

    local addButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addButton:SetSize(76, 22)
    addButton:SetPoint("TOPRIGHT", -60, -16)
    addButton:SetText("Add Task")
    styleFlatButton(addButton)
    addButton:SetScript("OnClick", function()
        createTaskForm():ShowForTask(nil)
    end)

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeButton:SetSize(28, 22)
    closeButton:SetPoint("TOPRIGHT", -22, -16)
    closeButton:SetText("X")
    styleFlatButton(closeButton, "danger")
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    local headerName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerName:SetPoint("TOPLEFT", 24, -54)
    headerName:SetWidth(205)
    headerName:SetFontObject(getThemeFont("small"))
    setTextColor(headerName, Theme.colors.muted)
    headerName:SetText("TASK NAME")

    local headerFrequency = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerFrequency:SetPoint("TOPLEFT", 235, -54)
    headerFrequency:SetWidth(58)
    headerFrequency:SetFontObject(getThemeFont("small"))
    setTextColor(headerFrequency, Theme.colors.muted)
    headerFrequency:SetText("TYPE")

    local headerStatus = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerStatus:SetPoint("TOPLEFT", 305, -54)
    headerStatus:SetWidth(70)
    headerStatus:SetFontObject(getThemeFont("small"))
    setTextColor(headerStatus, Theme.colors.muted)
    headerStatus:SetText("STATUS")

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 20, -72)
    scrollFrame:SetPoint("BOTTOMRIGHT", -42, 20)
    styleScrollArea(scrollFrame)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(1, 1)
    scrollFrame:SetScrollChild(scrollChild)

    local emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("TOP", scrollChild, "TOP", 0, -62)
    emptyText:SetWidth(480)
    emptyText:SetJustifyH("CENTER")
    emptyText:SetFontObject(getThemeFont("body"))
    setTextColor(emptyText, Theme.colors.muted)
    emptyText:SetText("No tasks yet. Add one to get started.")

    local function updateManageScrollWidth()
        local contentWidth = math.max(scrollFrame:GetWidth(), 1)
        scrollChild:SetWidth(contentWidth)
        emptyText:SetWidth(math.max(contentWidth - (Theme.spacing.large * 2), 1))
    end
    scrollFrame:HookScript("OnSizeChanged", updateManageScrollWidth)
    updateManageScrollWidth()

    frame.scrollFrame = scrollFrame
    frame.scrollChild = scrollChild
    frame.emptyText = emptyText
    frame.rows = {}
    frame.lastTaskListSignature = nil
    TaskMinder.ManageFrame = frame

    frame:SetScript("OnShow", function()
        updateManageScrollWidth()
        TaskMinder:RefreshManageWindow()
    end)

    return frame
end

function TaskMinder:RefreshManageWindow()
    local frame = self.ManageFrame
    if not frame or not frame:IsShown() then
        return
    end

    local tasks = getAllTasks()
    local signature = getManageListSignature(tasks)
    if signature == frame.lastTaskListSignature then
        return
    end

    frame.lastTaskListSignature = signature
    if #tasks == 0 then
        frame.emptyText:Show()
    else
        frame.emptyText:Hide()
    end

    for index, task in ipairs(tasks) do
        local row = frame.rows[index]
        if not row then
            row = createManageTaskRow(frame.scrollChild, index)
            frame.rows[index] = row
        end

        row.name:SetText(task.name)
        row.frequency:SetText(task.frequency == DAILY and "Daily" or "Weekly")
        row.status:SetText(task.completed and "Completed" or "Active")
        setTextColor(row.name, task.completed and Theme.colors.completed or Theme.colors.text)
        setTextColor(row.frequency, task.completed and Theme.colors.completed or Theme.colors.accentMuted)
        setTextColor(row.status, task.completed and Theme.colors.completed or Theme.colors.accent)
        row.tmBaseColor = task.completed and Theme.colors.surface or Theme.colors.row
        row.tmBackground:SetColorTexture(unpack(row.tmBaseColor))
        row.editButton.taskID = task.id
        row.deleteButton.taskID = task.id
        row:Show()
    end

    for index = #tasks + 1, #frame.rows do
        frame.rows[index]:Hide()
    end

    frame.scrollChild:SetHeight(math.max(#tasks * (Theme.rowHeights.manage + Theme.spacing.tiny), 1))
    frame.scrollFrame:SetVerticalScroll(0)
end

function TaskMinder:ToggleManageWindow()
    local frame = createManageWindow()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

StaticPopupDialogs["TASKMINDER_CONFIRM_DELETE"] = {
    text = "Delete task '%s'? This cannot be undone.",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self)
        TaskMinder:DeleteTask(self.data)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function positionMinimapButton(button)
    local angle = math.rad(TaskMinderDB.minimapAngle)
    local radius = (Minimap:GetWidth() / 2) + Theme.spacing.tiny
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function createMinimapButton()
    if TaskMinder.MinimapButton then
        return TaskMinder.MinimapButton
    end

    local button = CreateFrame("Button", "TaskMinderMinimapButton", Minimap, "BackdropTemplate")
    button:SetSize(28, 28)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    styleScrollArea(button)
    button:HookScript("OnEnter", function(self)
        self.tmBackground:SetColorTexture(unpack(Theme.colors.rowHover))
    end)
    button:HookScript("OnLeave", function(self)
        self.tmBackground:SetColorTexture(unpack(Theme.colors.surface))
    end)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 4, -4)
    icon:SetPoint("BOTTOMRIGHT", -4, 4)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnClick", function()
        TaskMinder:ToggleMainWindow()
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("TaskMinder")
        GameTooltip:AddLine("Left-click to toggle the checklist.", 0.52, 0.58, 0.65)
        GameTooltip:AddLine("Drag to reposition.", 0.52, 0.58, 0.65)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local cursorX, cursorY = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            local minimapX, minimapY = Minimap:GetCenter()
            cursorX = cursorX / scale
            cursorY = cursorY / scale
            TaskMinderDB.minimapAngle = math.deg(math.atan2(cursorY - minimapY, cursorX - minimapX))
            positionMinimapButton(self)
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    positionMinimapButton(button)
    TaskMinder.MinimapButton = button
    return button
end

TaskMinder:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" and addonName == ADDON_NAME then
        initializeDatabase()
        applyClassAccentColor()
        createMinimapButton()
        TaskMinder:RegisterEvent("PLAYER_LOGIN")
        TaskMinder:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        applyClassAccentColor()
        TaskMinder:RefreshExpiredTasks()
        if TaskMinderDB.isMainWindowShown then
            createMainWindow():Show()
        end
        if not TaskMinder.resetTicker then
            TaskMinder.resetTicker = C_Timer.NewTicker(60, function()
                local nextResetTimestamp = TaskMinder.nextPendingResetTimestamp
                if nextResetTimestamp and nextResetTimestamp <= GetServerTime() then
                    TaskMinder:RefreshExpiredTasks()
                end
            end)
        end
        TaskMinder:UnregisterEvent("PLAYER_LOGIN")
    end
end)
TaskMinder:RegisterEvent("ADDON_LOADED")

SLASH_TASKMINDER1 = "/taskminder"
SLASH_TASKMINDER2 = "/tm"
SlashCmdList.TASKMINDER = function()
    local succeeded, errorMessage = pcall(TaskMinder.ToggleMainWindow, TaskMinder)
    if not succeeded then
        print("|cffff5555TaskMinder error:|r " .. tostring(errorMessage))
    end
end
