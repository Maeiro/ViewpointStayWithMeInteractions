if isServer() then return end

local previous = ViewpointStayWithMeInteractionsClient
if previous and Events then
    if Events.OnPostUIDraw then Events.OnPostUIDraw.Remove(previous.drawHandler) end
    if Events.OnKeyPressed then Events.OnKeyPressed.Remove(previous.keyPressed) end
    if Events.OnMouseWheel and previous.mouseWheel then Events.OnMouseWheel.Remove(previous.mouseWheel) end
    previous.target = nil
    previous.heldFUntil = 0
    previous.nativeMenuReady = false
    if previous.nativeInteract and previous.nativeInteract.harvest == previous.nativeHarvest then
        previous.nativeInteract.harvest = previous.originalHarvest
    end
end

local Client = {
    panel = nil,
    target = nil,
    targetAt = 0,
    pageStack = {},
    selected = 1,
    dismissedBody = nil,
    heldFUntil = 0,
    lastBuild = 0,
    menuDirty = true,
    lightKeyWrapper = nil,
    buildErrorLogged = false,
    drawErrorLogged = false,
    stopped = false,
}
ViewpointStayWithMeInteractionsClient = Client

local TARGET_GRACE_MS = 150
local AIM_RADIUS = 1.2
local MAX_VISIBLE_ROWS = 12
local FONT = UIFont.Small

local function activeView()
    local addons = Viewpoint and Viewpoint.Addons
    if not addons or type(addons.viewState) ~= "function" then return nil end
    local ok, state = pcall(addons.viewState)
    if not ok or type(state) ~= "table" or state.on ~= true or state.freeCamera == true then return nil end
    if state.mode ~= "FIRST_PERSON" and state.mode ~= "THIRD_PERSON" then return nil end
    return state
end

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function visibleCompanion(player, state)
    local bridge = Bridge
    local menu = BridgeMenu
    local body = bridge and bridge.body
    local hit = state and state.crosshairHit
    if not body or not hit or not menu or type(menu.inTalkRange) ~= "function" then return nil end

    local ok, dead = pcall(body.isDead, body)
    if not ok or dead then return nil end

    local x, y, z
    local gotPosition = pcall(function() x, y, z = body:getX(), body:getY(), body:getZ() end)
    if not gotPosition or not finite(x) or not finite(y) or not finite(z)
            or not finite(hit.x) or not finite(hit.y) or not finite(hit.z) then return nil end
    local dx, dy = hit.x - x, hit.y - y
    if dx * dx + dy * dy > AIM_RADIUS * AIM_RADIUS or math.abs(hit.z - z) > 1.25 then return nil end

    local inRange = false
    local rangeOk = pcall(function() inRange = menu.inTalkRange() == true end)
    if not rangeOk or not inRange then return nil end

    if LosUtil and type(LosUtil.lineClear) == "function" then
        local clearOk, result = pcall(function()
            return LosUtil.lineClear(getCell(), math.floor(player:getX()), math.floor(player:getY()),
                math.floor(player:getZ()), math.floor(x), math.floor(y), math.floor(z), false)
        end)
        if clearOk and tostring(result):find("Blocked", 1, true) then return nil end
    end
    return body
end

local Context = {}
Context.__index = Context

function Context:addOption(label, target, onSelect, ...)
    local params = { ... }
    local option = {
        label = tostring(label or ""),
        target = target,
        onSelect = onSelect,
        params = params,
    }
    self.options[#self.options + 1] = option
    return option
end

function Context:addOptionOnTop(label, target, onSelect, ...)
    return self:addOption(label, target, onSelect, ...)
end

function Context:addSubMenu(option, submenu)
    option.submenu = submenu
end

local function newContext()
    return setmetatable({ options = {}, player = 0, viewpointStayWithMeContext = true }, Context)
end

local function buildMenu()
    local menu = BridgeMenu
    if not menu or type(menu.fill) ~= "function" or not ISContextMenu
            or type(ISContextMenu.getNew) ~= "function" then return nil end

    local root = newContext()
    local originalGetNew = ISContextMenu.getNew
    ISContextMenu.getNew = function(self, parent)
        if type(parent) == "table" and parent.viewpointStayWithMeContext == true then
            return newContext()
        end
        return originalGetNew(self, parent)
    end

    local ok, err = pcall(menu.fill, root, 0, false)
    ISContextMenu.getNew = originalGetNew
    if not ok then
        if not Client.buildErrorLogged then
            Client.buildErrorLogged = true
            print("[Stay With Me Viewpoint Interactions] menu build failed: " .. tostring(err))
        end
        return nil
    end
    Client.buildErrorLogged = false
    return root
end

local function backLabel()
    local key = "IGUI_ViewpointStayWithMeInteractions_Back"
    local label = getText(key)
    return label ~= key and label or "Back"
end

local function canSelect(option)
    return option and not option.notAvailable and not option.isDisabled
end

local function invoke(option)
    local params = option.params
    local ok, err = pcall(option.onSelect, option.target,
        params[1], params[2], params[3], params[4], params[5], params[6], params[7], params[8], params[9], params[10])
    if not ok then print("[Stay With Me Viewpoint Interactions] action failed: " .. tostring(err)) end
end

local function menuPage(menu, path)
    for _, label in ipairs(path) do
        local submenu
        for _, option in ipairs(menu.options) do
            if option.label == label and option.submenu and canSelect(option) then
                submenu = option.submenu
                break
            end
        end
        if not submenu then return nil end
        menu = submenu
    end
    return menu
end

local ACTION_ICONS = {
    Talk = "emotes/group.png",
    Talk_Chat = "emotes/comehere.png",
    Talk_Joke = "emotes/clap.png",
    Talk_Thanks = "emotes/thankyou.png",
    Talk_Ask = "emotes/undecided.png",
    Talk_Greetings = "emotes/wavehello.png",
    Affection = "Sidebar/64/Heart_Off_64.png",
    HealMe = "Sidebar/64/Heart_On_64.png",
    WindowEquip = "Sidebar/64/Inventory_Off_64.png",
    WaitHere = "emotes/stop.png",
    ComeWithMe = "emotes/followme.png",
    Rest = "emotes/sit_on.png",
    Exercise = "emotes/autowalk_on.png",
    Goodbye = "emotes/wavebye.png",
    Actions = "emotes/gears.png",
    Combat = "Sidebar/64/Safety_Tintable_64.png",
    GunMenu = "emotes/fire.png",
    OptTorch = "vehicles/vehicle_lightsON.png",
    OptTorchAuto = "vehicles/vehicle_lightsON.png",
    OptTorchOff = "vehicles/vehicle_lightsOFF.png",
    Jobs = "Sidebar/64/Carpentry_Off_64.png",
    CancelTask = "emotes/no.png",
}

local function actionIcons()
    local icons = {}
    if BridgeData and type(BridgeData.text) == "function" then
        for key, image in pairs(ACTION_ICONS) do
            local label = BridgeData.text(key)
            if type(label) == "string" then icons[label] = image end
        end
    end
    return icons
end

local function nativePage(interact, player, body)
    local playerNum = player:getPlayerNum()
    local open, reason = interact.menu(playerNum)
    if not open then return { why = reason } end
    local bridgeMenu = BridgeMenu
    if not bridgeMenu or not bridgeMenu.inTalkRange() then return { why = "companion out of range" } end
    local menu = assert(buildMenu(), "companion menu could not be built")
    local path = Client.nativePath or {}
    local page = menuPage(menu, path)
    if not page then path, page = {}, menu end
    Client.nativePath = path

    local icons = actionIcons()
    local defaultIcon = icons[path[#path]] or ACTION_ICONS.Actions
    local rows = {}
    local function addRow(name, option, action)
        local image = option and (icons[option.label] or defaultIcon) or "emotes/back.png"
        rows[#rows + 1] = {
            name = name,
            fn = function()
                if Client.nativeBody == body and Bridge and Bridge.body == body and not body:isDead()
                        and Client.nativePath == path and bridgeMenu.inTalkRange() then
                    action()
                end
            end,
            args = {},
            n = 0,
            menu = true,
            enabled = option == nil or canSelect(option),
            tip = option and option.toolTip,
            icon = (option and option.iconTexture) or getTexture("media/ui/" .. image),
        }
    end
    local function changePage(length, label)
        local nextPath = {}
        for i = 1, length do nextPath[i] = path[i] end
        if label then nextPath[length + 1] = label end
        Client.nativePath = nextPath
    end

    if #path > 0 then addRow(backLabel(), nil, function() changePage(#path - 1) end) end
    for _, option in ipairs(page.options) do
        if option.submenu and #option.submenu.options > 0 then
            local label = option.label
            addRow(label .. " >", option, function() changePage(#path, label) end)
        elseif type(option.onSelect) == "function" then
            local entry = option
            addRow(entry.label, entry, function() invoke(entry) end)
        end
    end
    local title = Bridge.companionName()
    if #path > 0 then title = title .. " / " .. path[#path] end
    interact.target = { object = body, square = body:getSquare() }
    local support = ViewpointExtendedSupport
    if support and type(support.clearVanillaContextMenuIcons) == "function" then
        pcall(support.clearVanillaContextMenuIcons)
    end
    return interact.finish(rows, title, #rows)
end

local function installNativeMenu()
    if Client.nativeHarvest then return end
    local interact = ViewpointInteract
    if not interact or type(interact.harvest) ~= "function" or type(interact.finish) ~= "function"
            or type(interact.menu) ~= "function" then return end
    Client.nativeHarvest = function(player, object)
        if Client.nativeMenuReady and Client.nativeActive and Client.nativeBody == object
                and Bridge and Bridge.body == object and not object:isDead() then
            local ok, result = pcall(nativePage, interact, player, object)
            if ok then return result end
            Client.nativeMenuReady = false
            Client.nativeActive = false
            Client.nativeBody = nil
            Client.nativePath = nil
            print("[Stay With Me Viewpoint Interactions] native menu failed; using Lua menu: " .. tostring(result))
            return { why = "companion menu unavailable" }
        end
        return interact.harvest(player, object)
    end
    Client.nativeMenuReady = true
end

local function currentPage()
    local entry = Client.pageStack[#Client.pageStack]
    return entry and entry.menu or nil
end

local function buildPage(body)
    if Client.target ~= body then
        Client.target = body
        Client.pageStack = {}
        Client.selected = 1
        Client.dismissedBody = nil
        Client.lastBuild = 0
        Client.menuDirty = true
    end

    local now = getTimestampMs()
    if #Client.pageStack == 0 or Client.menuDirty
            or (#Client.pageStack == 1 and now - Client.lastBuild >= 500) then
        local root = buildMenu()
        if root then
            if #Client.pageStack == 0 then
                Client.pageStack[1] = { menu = root, selected = 1 }
            else
                Client.pageStack[1].menu = root
                Client.selected = math.max(1, math.min(Client.pageStack[1].selected or Client.selected, #root.options))
                Client.pageStack[1].selected = Client.selected
            end
        end
        Client.menuDirty = false
        Client.lastBuild = now
    end
end

local function resetTarget()
    Client.target = nil
    Client.pageStack = {}
    Client.selected = 1
    Client.dismissedBody = nil
    Client.menuDirty = true
end

local function stepSelection(delta)
    local page = currentPage()
    local count = page and #page.options or 0
    if count < 1 then Client.selected = 1; return end
    local nextIndex = Client.selected + delta
    if nextIndex < 1 then nextIndex = count end
    if nextIndex > count then nextIndex = 1 end
    Client.selected = nextIndex
    local pageEntry = Client.pageStack[#Client.pageStack]
    if pageEntry then pageEntry.selected = Client.selected end
end

local function drawMenu(width, height)
    local page = currentPage()
    if not page or #page.options == 0 then return end

    local textManager = getTextManager()
    local fontHeight = textManager:getFontHeight(FONT)
    local rowHeight = fontHeight + 8
    local availableRows = math.max(1, math.floor((height - fontHeight * 5 - 32) / rowHeight))
    local visibleCount = math.min(MAX_VISIBLE_ROWS, #page.options, availableRows)
    local first = math.max(1, math.min(Client.selected - math.floor(visibleCount / 2), #page.options - visibleCount + 1))
    local last = first + visibleCount - 1
    local title = "Companion"
    if Bridge and type(Bridge.companionName) == "function" then
        local ok, name = pcall(Bridge.companionName)
        if ok and name ~= nil and tostring(name) ~= "" then title = tostring(name) end
    end
    local footer = getText("IGUI_ViewpointStayWithMeInteractions_Controls")
    if footer == "IGUI_ViewpointStayWithMeInteractions_Controls" then footer = "Scroll: select  F: choose" end
    local textWidth = math.max(textManager:MeasureStringX(FONT, title), textManager:MeasureStringX(FONT, footer), 150)
    for i = first, last do textWidth = math.max(textWidth, textManager:MeasureStringX(FONT, page.options[i].label)) end

    local pad, widthPad, head = 8, 24, fontHeight + 10
    local panelWidth = textWidth + widthPad
    local panelHeight = head + visibleCount * rowHeight + fontHeight + 12
    local x = math.floor(width / 2 + 48)
    local y = math.max(8, math.floor(height / 2 - panelHeight / 2))
    local panel = Client.panel
    panel:drawRect(x, y, panelWidth, panelHeight, 0.86, 0.05, 0.05, 0.06)
    panel:drawText(title, x + pad, y + 5, 1, 0.82, 0.35, 1, FONT)

    local rowY = y + head
    for i = first, last do
        local option = page.options[i]
        if i == Client.selected then
            panel:drawRect(x + 3, rowY, panelWidth - 6, rowHeight - 2, 0.16, 1, 1, 1)
        end
        local color = (option.notAvailable or option.isDisabled) and 0.45 or 1
        panel:drawText(option.label, x + pad, rowY + 3, color, color, color, 1, FONT)
        if option.submenu then panel:drawText(">", x + panelWidth - fontHeight, rowY + 3, 0.75, 0.75, 0.75, 1, FONT) end
        rowY = rowY + rowHeight
    end

    panel:drawText(footer, x + pad, rowY + 4, 0.72, 0.72, 0.72, 1, FONT)
    if first > 1 then panel:drawText("^", x + panelWidth - fontHeight - 2, y + head + 1, 0.72, 0.72, 0.72, 1, FONT) end
    if last < #page.options then panel:drawText("v", x + panelWidth - fontHeight - 2, rowY - rowHeight + 2, 0.72, 0.72, 0.72, 1, FONT) end
end

local function goBack()
    if #Client.pageStack <= 1 then return end
    table.remove(Client.pageStack)
    local page = Client.pageStack[#Client.pageStack]
    Client.selected = page and page.selected or 1
end

local function selectCurrent()
    local page = currentPage()
    local option = page and page.options[Client.selected]
    if not canSelect(option) then return end
    if option.isBack then
        goBack()
        return
    end
    if option.submenu then
        local current = Client.pageStack[#Client.pageStack]
        current.selected = Client.selected
        local options = { { label = backLabel(), isBack = true } }
        for i = 1, #option.submenu.options do
            options[#options + 1] = option.submenu.options[i]
        end
        Client.pageStack[#Client.pageStack + 1] = { menu = { options = options }, selected = math.min(2, #options) }
        Client.selected = math.min(2, #options)
        Client.lastBuild = getTimestampMs()
        return
    end
    if type(option.onSelect) == "function" then
        invoke(option)
        Client.pageStack = {}
        Client.selected = 1
        Client.dismissedBody = Client.target
        Client.menuDirty = true
        Client.lastBuild = 0
    end
end

function Client.keyPressed(key)
    if Client.nativeActive or not Client.target then return end
    if key == Keyboard.KEY_F then
        Client.heldFUntil = getTimestampMs() + 250
        selectCurrent()
    end
end

function Client.mouseWheel(delta)
    delta = tonumber(delta) or 0
    if Client.nativeActive or delta == 0 or not Client.target or Client.dismissedBody == Client.target then return end
    if not currentPage() then return end
    stepSelection(delta < 0 and 1 or -1)
end

local wrapLightKey

function Client.draw()
    installNativeMenu()
    if Client.nativeActive then
        if Client.target then resetTarget() end
        if Client.nativeBody and not activeView() then
            Client.nativeBody = nil
            Client.nativePath = nil
        end
        return
    end
    wrapLightKey()
    local state = activeView()
    local player = getSpecificPlayer(0)
    if not state or not player or player:isDead() then resetTarget(); return end

    local body = visibleCompanion(player, state)
    local now = getTimestampMs()
    if body then
        Client.targetAt = now
    elseif not Client.target or now - Client.targetAt > TARGET_GRACE_MS then
        resetTarget()
        return
    end

    if body and Client.dismissedBody == body then return end
    body = body or Client.target
    if not body then return end
    buildPage(body)

    local core = getCore()
    local width, height = core:getScreenWidth(), core:getScreenHeight()
    if not Client.panel then
        Client.panel = ISUIElement:new(0, 0, width, height)
        Client.panel:initialise()
        Client.panel:instantiate()
    end
    Client.panel:setWidth(width)
    Client.panel:setHeight(height)
    drawMenu(width, height)
end

wrapLightKey = function()
    local radial = ISLightSourceRadialMenu
    if not radial or type(radial.checkKey) ~= "function" or radial.checkKey == Client.lightKeyWrapper then return end
    local original = radial.checkKey
    Client.lightKeyWrapper = function(key, ...)
        if key == Keyboard.KEY_F and not Client.nativeActive
                and (Client.target ~= nil or getTimestampMs() < Client.heldFUntil) then return false end
        return original(key, ...)
    end
    radial.checkKey = Client.lightKeyWrapper
end

Client.drawHandler = function()
    if Client.stopped then return end
    local ok, err = pcall(Client.draw)
    if not ok then
        Client.stopped = true
        resetTarget()
        Client.heldFUntil = 0
        if not Client.drawErrorLogged then
            Client.drawErrorLogged = true
            print("[Stay With Me Viewpoint Interactions] stopped after an error: " .. tostring(err))
        end
    end
end

if Events then
    if Events.OnPostUIDraw then Events.OnPostUIDraw.Add(Client.drawHandler) end
    if Events.OnKeyPressed then Events.OnKeyPressed.Add(Client.keyPressed) end
    if Events.OnMouseWheel then Events.OnMouseWheel.Add(Client.mouseWheel) end
end
wrapLightKey()
