function widget:GetInfo()
	return {
        name      = "Key Tracker",
        desc      = "Displays pressed keys on the screen",
        author    = "MasterBel2",
        date      = "January 2022",
        license   = "GNU GPL, v2",
        layer     = math.huge, -- must be in front
        enabled   = true, --enabled by default
        handler   = true
	}
end

------------------------------------------------------------------------------------------------------------
-- Includes
------------------------------------------------------------------------------------------------------------

local MasterFramework
local requiredFrameworkVersion = "Dev"

local Spring_GetPressedKeys = Spring.GetPressedKeys

------------------------------------------------------------------------------------------------------------
-- Keyboard
------------------------------------------------------------------------------------------------------------

local trackerKey
local keyboardKey

local label

------------------------------------------------------------------------------------------------------------
-- Interface
------------------------------------------------------------------------------------------------------------

local uiKeys = {}
local pressedUIKeys = {}

local heatmap = {}
local modifiedHeatmap = {}
local showHeatmap = false
local maxPressedtime = 0

local elapsedTime = 0

------------------------------------------------------------------------------------------------------------
-- Stats Data
------------------------------------------------------------------------------------------------------------

local statsCategory

local totalKeysPressed = 0

-- Vertices - x, y
local myKeypressData = {
    { 0, 0 }
}

local graphData = {
    discrete = true,
    lines = {
        { 
            color = { r = 0, g = 0, b = 1, a = 1 }, 
            vertices = myKeypressData 
        }
    }
}

------------------------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------------------------

local table_concat = table.concat

function string:remove(i) -- incomplete consideration of edge cases, but due to our use here we won't flesh that out yet. (Should this be public then?)
    if #self > i then 
        return self:sub(1, i - 1) .. self:sub(i + 1, #self)
    elseif #self == i then
        return self:sub(1, i - 1)
    else
        return self 
    end
end

------------------------------------------------------------------------------------------------------------
-- Widget Events (Update, Initialize, Shutdown)
------------------------------------------------------------------------------------------------------------

function widget:Initialize()
    if WG.MasterStats then WG.MasterStats:Refresh() end

    MasterFramework = WG["MasterFramework " .. requiredFrameworkVersion]
    if not MasterFramework then
        Spring.Echo("[Key Tracker] Error: MasterFramework " .. requiredFrameworkVersion .. " not found! Removing self.")
        widgetHandler:RemoveWidget(self)
        return
    end

    widgetHandler.actionHandler:AddAction(
        self,
        "master_keytracker_heatmap_visible", 
        function(_, _, words)
            showHeatmap = (words[1] == "1")

            if not showHeatmap then
                for code, key in pairs(uiKeys) do
                    key:SetPressed(pressedUIKeys[code] ~= nil)
                end
            end
        end,
        nil,
        "t"
    )

    -- Interface structure

    label = MasterFramework:Text("", nil, nil, nil, MasterFramework:Font("Poppins-Regular.otf", 28, 0.2, 1.3))

    local keyboard = WG.MasterGUIKeyboard()
    uiKeys = keyboard.uiKeys

    keyboardKey, keyboardElement = MasterFramework:InsertElement(
        MasterFramework:FrameOfReference(0.5, 0, MasterFramework:PrimaryFrame(keyboard)),
        "Key Tracker Keyboard",
        MasterFramework.layerRequest.anywhere()
    )

    if MasterFramework:GetDebugMode() then
        trackerKey = MasterFramework:InsertElement(
            MasterFramework:FrameOfReference(
                0.9,
                0.9,
                MasterFramework:PrimaryFrame(label)
            ), 
            "Key Tracker",
            MasterFramework.layerRequest.top()
        )
    end
end

local function modifiersToBitfield(alt, ctrl, meta, shift)
    local bitfield = 0
    if alt then bitfield = bitfield + 1 end
    if ctrl then bitfield = bitfield + 2 end
    if meta then bitfield = bitfield + 4 end
    if shift then bitfield = bitfield + 8 end
    return bitfield
end

function widget:Update(dt)
    elapsedTime = elapsedTime + dt

    local wasPressed = pressedUIKeys
    pressedUIKeys = {}

    local keys = {}

    local pressedScans = Spring.GetPressedScans()
    for codeOrName, isPressed in pairs(pressedScans) do
        if isPressed and type(codeOrName) == "string" then
            table.insert(keys, codeOrName .. "(" .. Spring.GetKeyCode(Spring.GetKeyFromScanSymbol(codeOrName)) .. ")")
            local keyCode = Spring.GetKeyCode(Spring.GetKeyFromScanSymbol(codeOrName))

            pressedUIKeys[keyCode] = uiKeys[keyCode]

            heatmap[keyCode] = (heatmap[keyCode] or 0) + dt
            maxPressedtime = math.max(maxPressedtime, heatmap[keyCode])
        end
    end

    -- local pressedKeys = Spring_GetPressedKeys()

    local newTotalKeypresses = totalKeysPressed

    -- for codeOrName, isPressed in pairs(pressedKeys) do
    --     if isPressed and type(codeOrName) == "number" then
    --         table.insert(keys, tostring(codeOrName))
    --         pressedUIKeys[codeOrName] = uiKeys[codeOrName]

    --         heatmap[codeOrName] = (heatmap[codeOrName] or 0) + dt
    --         maxPressedtime = math.max(maxPressedtime, heatmap[codeOrName])
    --     end
    -- end
    local pressedModifiers = modifiersToBitfield(
        pressedUIKeys[0x134],
        pressedUIKeys[0x132],
        pressedUIKeys[0x136],
        pressedUIKeys[0x130]
    )
    for key, uiKey in pairs(pressedUIKeys) do
        if not wasPressed[key] then
            newTotalKeypresses = newTotalKeypresses + 1
            uiKey:SetPressed(true)

            if not (widgetHandler.textOwner or key == 0x130 or key == 0x132 or key == 0x134 or key == 0x136) then
                local perModifier = modifiedHeatmap[pressedModifiers] or {}
                perModifier[key] = (perModifier[key] or 0) + 1
                modifiedHeatmap[pressedModifiers] = perModifier
            end 
        end
    end
    for key, uiKey in pairs(wasPressed) do
        if not pressedUIKeys[key] then
            uiKey:SetPressed(false)
        end
    end

    -- label:SetString(table_concat(keys, " + "))

    if showHeatmap then
        for code, time in pairs(heatmap) do
            if uiKeys[code] then
                uiKeys[code]:SetBackgroundColor({ r = time / maxPressedtime, g = 1 - (time / maxPressedtime), b = 0 })
            else
                -- For SDL1, Code 310 (Left Meta) triggers this pathng
            end
        end
    end

    if newTotalKeypresses ~= totalKeysPressed then
        table.insert(myKeypressData, { elapsedTime, newTotalKeypresses })
        totalKeysPressed = newTotalKeypresses
    end
end

local function writeHeatmap()
    local file = io.open("LuaUI/Config/heatmap.json", "w")
    file:write(Json.encode(modifiedHeatmap))
    file:close()
end

function widget:GameOver()
    if not (Spring.GetSpectatingState() or Spring.GetGameFrame() < 30 * 60 * 10) then
        Spring.Echo("Writing heatmap!")
        writeHeatmap()
    else
        Spring.Echo("Not writing heatmap!", Spring.GetSpectatingState(), Spring.GetGameFrame())
    end

    Spring.Echo("Game over!")
    showHeatmap = true
end

function widget:Shutdown()
    if not (Spring.GetSpectatingState() or Spring.GetGameFrame() < 30 * 60 * 15 or Spring.IsGameOver()) then
        writeHeatmap()
    else
        Spring.Echo("Not writing heatmap!", Spring.GetSpectatingState(), Spring.GetGameFrame(), Spring.IsGameOver())
    end

    MasterFramework:RemoveElement(trackerKey)
    MasterFramework:RemoveElement(keyboardKey)

    widgetHandler.actionHandler:RemoveAction(self, "master_keytracker_heatmap_visible", "t")
end

function widget:MasterStatsCategories()
    return {
        Input = {
            ["Keypress Count"] = graphData
        }
    }
end