-- hotbartobelt.lua
local M = {}

-- SETTINGS

local PART_PREFIX = "belt_slot_"
local SCAN_INTERVAL = 5
local RESYNC_EVERY_SCANS = 8
local DEFAULT_SCALE = 0.2
local MAX_STACK_STRING = 400
local AIR = "minecraft:air"

-- Components that change how an item LOOKS. Add more if you need them.
local MODEL_COMPONENTS = {
    "minecraft:custom_model_data",
    "minecraft:item_model",
    "minecraft:potion_contents",
    "minecraft:dyed_color",
    "minecraft:trim",
    "minecraft:banner_patterns",
    "minecraft:base_color",
}

local DEFAULT_HOTBAR = {}
for i = 0, 8 do DEFAULT_HOTBAR[#DEFAULT_HOTBAR + 1] = i end

local DEFAULT_SEARCH_SLOTS = {}
for i = 0, 35 do DEFAULT_SEARCH_SLOTS[#DEFAULT_SEARCH_SLOTS + 1] = i end

local instances = {}
local nextAutoId = 1

-- AUXILIARY FUNCTIONS

local function escapeString(str)
    str = tostring(str)
    str = str:gsub("\\", "\\\\")
    str = str:gsub("\"", "\\\"")
    return str
end

local function asList(value)
    if value == nil then
        return nil
    end
    if type(value) == "string" then
        return { value }
    end
    return value
end

-- "minecraft:apple", "apple" and "mymod:*" are all valid
local function idMatches(patterns, id)
    for _, pattern in ipairs(patterns) do
        if not pattern:find(":", 1, true) then
            pattern = "minecraft:" .. pattern
        end
        if pattern:sub(-1) == "*" then
            if id:sub(1, #pattern - 1) == pattern:sub(1, -2) then
                return true
            end
        elseif pattern == id then
            return true
        end
    end
    return false
end

local function passesRules(rules, id)
    if rules.blacklist and idMatches(rules.blacklist, id) then
        return false
    end
    if rules.whitelist and not idMatches(rules.whitelist, id) then
        return false
    end
    if rules.filter and not rules.filter(id) then
        return false
    end
    return true
end

local function warn(self, message)
    if host:isHost() then
        print("[BeltDisplay:" .. self.id .. "] " .. message)
    end
end

-- LUA TABLE -> SNBT

local function toSnbt(value)
    local t = type(value)

    if t == "string" then
        return "\"" .. escapeString(value) .. "\""

    elseif t == "boolean" then
        return tostring(value)

    elseif t == "number" then
        if value == math.floor(value) and math.abs(value) < 2 ^ 31 then
            return string.format("%d", value)
        end
        return tostring(value)

    elseif t == "table" then
        if next(value) == nil then
            return nil
        end

        local out = {}

        if value[1] ~= nil then
            for _, entry in ipairs(value) do
                local s = toSnbt(entry)
                if s then
                    out[#out + 1] = s
                end
            end
            return "[" .. table.concat(out, ",") .. "]"
        end

        for key, entry in pairs(value) do
            local s = toSnbt(entry)
            if s then
                out[#out + 1] = "\"" .. escapeString(key) .. "\":" .. s
            end
        end
        return "{" .. table.concat(out, ",") .. "}"
    end

    return nil
end

-- BUILDING A COMPACT ITEMSTACK STRING

local function getComponent(tag, name)
    local value = tag[name]
    if value == nil then
        value = tag[(name:gsub("^minecraft:", ""))]
    end
    return value
end

local function hasEnchantments(tag)
    local e = getComponent(tag, "minecraft:enchantments")
    if type(e) ~= "table" then
        return false
    end
    if type(e.levels) == "table" then
        e = e.levels
    end
    return next(e) ~= nil
end

local function buildStack(item, id)
    local tag = item:getTag()
    if type(tag) ~= "table" then
        return id
    end

    local components = {}

    for _, name in ipairs(MODEL_COMPONENTS) do
        local value = getComponent(tag, name)
        if value ~= nil then
            local snbt = toSnbt(value)
            if snbt then
                components[#components + 1] = name .. "=" .. snbt
            end
        end
    end

    -- enchantment glint (pretty cheap, it's just a boolean instead of the whole enchant list)
    local glint = getComponent(tag, "minecraft:enchantment_glint_override")
    if type(glint) == "number" then
        glint = glint ~= 0
    end
    if glint == nil and hasEnchantments(tag) then
        glint = true
    end
    if glint ~= nil then
        components[#components + 1] =
            "minecraft:enchantment_glint_override=" .. tostring(glint)
    end

    if #components == 0 then
        return id
    end

    local result = id .. "[" .. table.concat(components, ",") .. "]"
    if #result > MAX_STACK_STRING then
        return id
    end
    return result
end

-- SELECTED HOTBAR SLOT

local cachedTime = -1
local cachedSelected = nil

local function getSelectedSlot()
    local now = world.getTime()
    if now ~= cachedTime then
        cachedTime = now
        local nbt = player:getNbt()
        cachedSelected = nbt and nbt.SelectedItemSlot or nil
    end
    return cachedSelected
end

-- BELT CLASS

local Belt = {}
Belt.__index = Belt

function Belt:addChannel(part, cfg, defaults, sources)
    local index = #self.channels + 1

    local scale = cfg.scale or defaults.scale
    if type(scale) == "number" then
        scale = vectors.vec3(scale, scale, scale)
    end

    local task = part:newItem(self.id .. "_item_" .. index)
        :setDisplayMode(cfg.displayMode or defaults.displayMode)
        :setScale(scale)
        :setVisible(true)

    self.channels[index] = {
        task    = task,
        sources = sources,
        source  = nil,      -- slot currently feeding this channel (per host)
        filled  = false,
        rules   = {
            whitelist = asList(cfg.whitelist) or defaults.rules.whitelist,
            blacklist = asList(cfg.blacklist) or defaults.rules.blacklist,
            filter    = cfg.filter or defaults.rules.filter,
        },
    }
end

-- CLIENT SIDE

function Belt:refreshVisibility(ch)
    local hidden = self.hideWhenHeld
        and ch.source ~= nil
        and ch.source == self.selected
    ch.task:setVisible(not hidden)
end

function Belt:refreshCarrier()
    if not self.carrier then
        return
    end

    local any = false
    for _, ch in ipairs(self.channels) do
        if ch.filled then
            any = true
            break
        end
    end
    self.carrier:setVisible(any)
end

function Belt:apply(index, stackString, source)
    local ch = self.channels[index]
    if not ch then
        return
    end

    if source == -1 then
        source = nil
    end
    ch.source = source
    ch.filled = false

    if stackString and stackString ~= "" and stackString ~= AIR then
        local ok, item = pcall(world.newItem, stackString)
        if ok and item then
            ch.task:setItem(item)
            ch.filled = true
        end
    end

    if not ch.filled then
        ch.task:setItem(AIR)
    end

    self:refreshVisibility(ch)
    self:refreshCarrier()
end

function Belt:applyHeld(selected)
    self.selected = selected
    for _, ch in ipairs(self.channels) do
        self:refreshVisibility(ch)
    end
end

-- PINGS

function pings.beltDisplaySlot(id, index, stackString, source)
    local inst = instances[id]
    if inst then
        inst:apply(index, stackString, source)
    end
end

function pings.beltDisplayHeld(id, selected)
    local inst = instances[id]
    if inst then
        inst:applyHeld(selected)
    end
end

-- HOST SIDE

function Belt:resolve(ch)
    for _, slot in ipairs(ch.sources) do
        local item = host:getSlot(slot)
        if item then
            local id = item:getID()
            if id and id ~= AIR and passesRules(ch.rules, id) then
                return buildStack(item, id), slot
            end
        end
    end
    return AIR, nil
end

function Belt:send(index)
    local last = self.lastSent[index]
    pings.beltDisplaySlot(self.id, index, last.stack, last.source or -1)
end

function Belt:tick()

    -- SELECTED SLOT (checked every tick, it's cheap)

    if self.hideWhenHeld then
        local selected = getSelectedSlot()
        if selected ~= nil and selected ~= self.lastSelected then
            self.lastSelected = selected
            pings.beltDisplayHeld(self.id, selected)
        end
    end

    -- SCAN EVERY SCAN_INTERVAL TICKS

    if world.getTime() % SCAN_INTERVAL ~= 0 then
        return
    end

    self.scanCount = self.scanCount + 1
    local budget = self.maxPings

    -- SEND ONLY CHANGED CHANNELS

    for index, ch in ipairs(self.channels) do
        if budget <= 0 then
            break
        end

        local stack, source = self:resolve(ch)
        local last = self.lastSent[index]

        if last == nil and stack == AIR then
            self.lastSent[index] = { stack = stack, source = source }

        elseif last == nil or last.stack ~= stack or last.source ~= source then
            self.lastSent[index] = { stack = stack, source = source }
            self:send(index)
            budget = budget - 1

            if self.debug then
                print("[BeltDisplay:" .. self.id .. "] channel " .. index
                    .. " -> " .. stack)
            end
        end
    end

    -- ROUND-ROBIN RESYNC

    local count = #self.channels
    if budget > 0 and count > 0 then
        local index = self.resyncIndex
        self.resyncIndex = index % count + 1
        if self.lastSent[index] then
            self:send(index)
        end
    end

    if self.hideWhenHeld
        and self.lastSelected ~= nil
        and self.scanCount % RESYNC_EVERY_SCANS == 0 then
        pings.beltDisplayHeld(self.id, self.lastSelected)
    end
end

-- CONSTRUCTOR

function M.new(belt, config)
    if belt == nil then
        error("[BeltDisplay] the belt part is nil - check your model path "
            .. "(e.g. models.model.root.Body.Belt) and that the names match "
            .. "your Blockbench groups exactly", 2)
    end

    config = config or {}

    local self = setmetatable({}, Belt)
    self.id           = config.id or ("belt" .. nextAutoId)
    nextAutoId        = nextAutoId + 1
    self.debug        = config.debug == true
    self.hideWhenHeld = config.hideWhenHeld ~= false
    self.maxPings     = config.maxPingsPerScan or 3
    self.carrier      = config.carrier
    self.channels     = {}
    self.lastSent     = {}
    self.selected     = nil
    self.lastSelected = nil
    self.scanCount    = 0
    self.resyncIndex  = 1

    if instances[self.id] then
        warn(self, "duplicate belt id - give each belt its own id = \"...\"")
    end
    instances[self.id] = self

    local defaults = {
        scale       = config.scale or DEFAULT_SCALE,
        displayMode = config.displayMode or "FIXED",
        rules       = {
            whitelist = asList(config.whitelist),
            blacklist = asList(config.blacklist),
            filter    = config.filter,
        },
    }
--
    -- SLOT CHANNELS: one display per inventory slot--

    local slotConfig = config.slotConfig or {}
    local slots = config.slots
    if slots == nil and config.channels == nil then
        slots = DEFAULT_HOTBAR
    end

    for _, slot in ipairs(slots or {}) do
        local sc = slotConfig[slot] or {}
        local partName = PART_PREFIX .. tostring(slot)
        local part = sc.part or belt[partName]

        if part == nil then
            warn(self, "no model part named '" .. partName .. "' under the belt "
                .. "(hotbar slot 1 is belt_slot_0) - skipping slot "
                .. tostring(slot))
        else
            self:addChannel(part, sc, defaults, { slot })
        end
    end
--
    -- ITEM CHANNELS: show a specific item if it's ANYWHERE

    for i, cc in ipairs(config.channels or {}) do
        if cc.part == nil then
            warn(self, "channel " .. i .. " has no 'part' - skipping it")
        elseif cc.items == nil then
            warn(self, "channel " .. i .. " has no 'items' - skipping it")
        else
            local cfg = {
                scale       = cc.scale,
                displayMode = cc.displayMode,
                whitelist   = cc.items,
                blacklist   = cc.blacklist,
                filter      = cc.filter,
            }
            self:addChannel(cc.part, cfg, defaults,
                cc.searchSlots or DEFAULT_SEARCH_SLOTS)
        end
    end

    if self.carrier then
        self.carrier:setVisible(false)
    end
--
    -- ONLY THE HOST RUNS THE TICK--

    if host:isHost() then
        local function onTick()
            self:tick()
        end
        events.tick:register(onTick, "BeltDisplay_" .. self.id)
    end

    return self
end

-- backwards compatible with the old version!
M.init = M.new

return M