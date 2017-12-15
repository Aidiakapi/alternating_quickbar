local QUICKBAR_SIZE = 10

-- I still consider this rediculousness a bug, but whatever...
-- https://forums.factorio.com/viewtopic.php?t=54895
local function swap_stack(a, b)
    if a.valid_for_read or b.valid_for_read then
        a.swap_stack(b)
    else
        -- Assumes nobody removed iron-plate, if they did
        -- they'd also break the default scenario so...
        a.set_stack({ name = 'iron-plate', count = 1 })
        a.swap_stack(b)
        b.set_stack(nil)
    end
end

local function load_swap_logic(player)
    local quickbar = player.get_quickbar()

    if quickbar == nil then return 0 end

    local row_count = #quickbar / QUICKBAR_SIZE
    return row_count, function (a, b)
        if a == b then return end

        a = (a - 1) * QUICKBAR_SIZE + 1
        b = (b - 1) * QUICKBAR_SIZE + 1

        -- Reset active filters
        local filters = {}
        for i = 1, QUICKBAR_SIZE do
            filters[i] = quickbar.get_filter(a + i - 1)
            filters[i + QUICKBAR_SIZE] = quickbar.get_filter(b + i - 1)
            quickbar.set_filter(a + i - 1, nil)
            quickbar.set_filter(b + i - 1, nil)
        end
        
        -- Swap the slots
        for i = 0, QUICKBAR_SIZE - 1 do
            swap_stack(quickbar[a + i], quickbar[b + i])
        end

        -- Restore active filters
        for i = 1, QUICKBAR_SIZE do
            quickbar.set_filter(a + i - 1, filters[i + QUICKBAR_SIZE])
            quickbar.set_filter(b + i - 1, filters[i])
        end
    end
end

script.on_init(function ()
    script.on_event(defines.events.on_tick, function ()
        script.on_event(defines.events.on_tick, nil)
        for _, player in pairs(game.players) do
            player.print({ "general.welcome_message" })
        end
    end)
end)

local function get_pair_index(player)
    local aq = global.alternating_quickbar
    if not aq then aq = {} global.alternating_quickbar = aq end
    local idx = aq[player.index]
    if idx ~= nil then return idx end
    aq[player.index] = 1
    return 1
end
local function set_pair_index(player, index)
    local aq = global.alternating_quickbar
    if not aq then aq = {} global.alternating_quickbar = aq end
    aq[player.index] = index
end

script.on_event('aq_quickbar_swap', function (event)
    local player = game.players[event.player_index]
    -- player.print('Swap pressed')
    
    local quickbar_count, swap_quickbar = load_swap_logic(player)
    if quickbar_count < 2 then
        return
    end

    -- Don't swap if it's a 1 bar pair
    local idx = get_pair_index(player)
    if idx * 2 <= quickbar_count then
        swap_quickbar(1, 2)
    end

    -- Move all bars one down to undo what the default behavior that will happen AFTER this method
    swap_quickbar(1, quickbar_count)
    for i = quickbar_count - 1, 2, -1 do
        swap_quickbar(i, i + 1)
    end
end)
script.on_event('aq_quickbar_rotate', function (event)
    local player = game.players[event.player_index]
    -- player.print('Rotate pressed')
    
    local quickbar_count, swap_quickbar = load_swap_logic(player)
    if quickbar_count == 0 then
        player.print('No quickbar found on player')
        return
    end
    if quickbar_count == 1 then
        return
    end

    local pair_count = math.ceil(quickbar_count / 2)
    local idx = get_pair_index(player)
    
    if idx > pair_count then
        player.print('Warning: There are less quickbars than there used to be, you may have to reconfigure your quickbars.')
        idx = 1
    end

    if pair_count <= 1 then
        return
    end
    
    local pair_size = idx * 2 <= quickbar_count and 2 or 1
    -- player.print('Idx: ' .. idx .. ' PS: ' .. tostring(pair_size))

    for _ = 1, pair_size do
        for i = 1, quickbar_count - 1 do
            swap_quickbar(i, i + 1)
        end
    end

    idx = idx + 1
    if idx > pair_count then idx = 1 end
    set_pair_index(player, idx)
end)