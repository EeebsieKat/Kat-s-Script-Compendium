local M = {}

local beltTasks = {}
local beltPart = nil
local activeSlots = {}

local lastSlotData = {}
local lastSelectedSlot = -1

local tickTimer = 0
local syncTimer = 0

------------------------------------------------------------
-- INIT
------------------------------------------------------------

function M.init(belt, config)
    beltPart = belt
    config = config or {}

    activeSlots = config.slots or {
        0, 1, 2, 3, 4, 5, 6, 7, 8
    }

    for _, slot in ipairs(activeSlots) do
        local partName = "belt_slot_" .. slot
        local taskName = "belt_item_" .. slot

        beltTasks[slot] = belt[partName]:newItem(taskName)
            :setDisplayMode("FIXED")
            :setScale(0.55, 0.55, 0.55)
            :setVisible(true)
        lastSlotData[slot] = nil
    end
end

------------------------------------------------------------
-- AUXILIARY FUNCTIONS
------------------------------------------------------------

local function escapeString(str)
    str = tostring(str)

    str = str:gsub("\\", "\\\\")
    str = str:gsub("\"", "\\\"")
    return str
end

------------------------------------------------------------
-- CONVERTING AN ARRAY TO A STRING
------------------------------------------------------------

local function serializeArray(array, isString)
    if not array then
        return nil
    end

    local result = {}

    for i, value in ipairs(array) do
        if isString then
            result[#result + 1] =
                "\"" .. escapeString(value) .. "\""
        elseif type(value) == "boolean" then
            result[#result + 1] =
                tostring(value)
        else
            result[#result + 1] =
                tostring(value)
        end
    end
    return "[" .. table.concat(result, ",") .. "]"
end


------------------------------------------------------------
-- CREATING A COMPACT ITEMSTACK STRING
--
-- Only data that affects the model.
------------------------------------------------------------

local function makeModelStack(item)

    if not item then
        return "minecraft:air"
    end

    local id = item:getID()

    if not id then
        return "minecraft:air"
    end

    local components = {}
    local tag = item:getTag()

    --------------------------------------------------------
    -- CUSTOM MODEL DATA
    --------------------------------------------------------

    if tag and tag["minecraft:custom_model_data"] then
        local cmd = tag["minecraft:custom_model_data"]

        ----------------------------------------------------
        -- FLOATS
        ----------------------------------------------------

        if cmd.floats then
            local floats = serializeArray(
                cmd.floats,
                false
            )
            if floats then
                components[#components + 1] =
                    "minecraft:custom_model_data=" ..
                    "{floats:" .. floats .. "}"
            end
        end
    end

    --------------------------------------------------------
    -- ITEM MODEL
    --------------------------------------------------------

    if tag and tag["minecraft:item_model"] then
        local itemModel = tag["minecraft:item_model"]
        if type(itemModel) == "string" then
            components[#components + 1] =
                "minecraft:item_model=\"" ..
                escapeString(itemModel) ..
                "\""
        end
    end

    --------------------------------------------------------
    -- COMBINING ITEMSTACK
    --------------------------------------------------------

    if #components == 0 then
        return id
    end

    return id ..
        "[" ..
        table.concat(components, ",") ..
        "]"
end

------------------------------------------------------------
-- RECEIVING AN ITEM ON OTHER CLIENTS
------------------------------------------------------------

local function syncSlot(slot, stackString)
    if not beltTasks[slot] then
        return
    end

    if not stackString or stackString == "" then
        beltTasks[slot]:setItem("minecraft:air")
        return
    end

    local item = world.newItem(stackString)

    if item then
        beltTasks[slot]:setItem(item)
    else
        beltTasks[slot]:setItem("minecraft:air")
    end
end
pings.syncBeltSlot = syncSlot

------------------------------------------------------------
-- SYNCHRONIZATION OF THE SELECTED SLOT
------------------------------------------------------------

local function syncSelectedSlot(selectedSlot)
    for _, slot in ipairs(activeSlots) do
        if beltTasks[slot] then
            beltTasks[slot]:setVisible(
                slot ~= selectedSlot
            )
        end
    end
end

pings.syncSelectedSlot = syncSelectedSlot


------------------------------------------------------------
-- TICK
------------------------------------------------------------

function events.tick()

    if not player:isLoaded() or beltPart == nil then
        return
    end


    --------------------------------------------------------
    -- ONLY HOST
    --------------------------------------------------------

    if not host then
        return
    end


    --------------------------------------------------------
    -- PLAYER's NBT 
    --------------------------------------------------------

    local nbt = player:getNbt()

    if not nbt then
        return
    end


    --------------------------------------------------------
    -- SELECTED SLOT
    --------------------------------------------------------

    local selectedSlot = nbt.SelectedItemSlot

    if selectedSlot ~= nil
        and selectedSlot ~= lastSelectedSlot then
        lastSelectedSlot = selectedSlot
        pings.syncSelectedSlot(selectedSlot)
    end

    --------------------------------------------------------
    -- REFRESHING ITEMS EVERY 5 TICKS (0.25 SECONDS)
    --------------------------------------------------------

    tickTimer = tickTimer + 1
    if tickTimer < 5 then
        return
    end
    tickTimer = 0


    --------------------------------------------------------
    -- GETTING ITEMS
    --------------------------------------------------------

    local currentSlotData = {}

    for _, slot in ipairs(activeSlots) do
        local item = host:getSlot(slot)
        currentSlotData[slot] =
            makeModelStack(item)

    end

    --------------------------------------------------------
    -- SENDING ONLY CHANGED ITEMS
    --------------------------------------------------------

    for slot, stackString in pairs(currentSlotData) do
        if lastSlotData[slot] ~= stackString then
            lastSlotData[slot] = stackString
            pings.syncBeltSlot(
                slot,
                stackString
            )
        end
    end

    --------------------------------------------------------
    -- FULL SYNCHRONIZATION
    --
    -- Every 40 ticks = 2 seconds
    --------------------------------------------------------

    syncTimer = syncTimer + 5

    if syncTimer >= 40 then
        syncTimer = 0

        for slot, stackString in pairs(currentSlotData) do
            pings.syncBeltSlot(
                slot,
                stackString
            )
        end

        if selectedSlot ~= nil then
            pings.syncSelectedSlot(
                selectedSlot
            )
        end
    end
end

return M