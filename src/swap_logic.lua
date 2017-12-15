local function load_swap_logic(p)
    local QUICKBAR_SIZE = 10

    local q = p.get_quickbar()

    if q == nil then
        return 0, function () end
    end

    local function print(...)
        return p.print(...)
    end
    local function print_array(array, n)
        n = n or #array
        local c = {}
        for i = 1, n do
            c[#c + 1] = '['
            c[#c + 1] = tostring(i)
            c[#c + 1] = ']: '
            c[#c + 1] = tostring(array[i])
            if i ~= n then
                c[#c + 1] = ', '
            end
        end
        p.print(table.concat(c))
    end

    local ROW_COUNT = #q / QUICKBAR_SIZE

    local is_unfiltered_slot
    do
        local iron = { name = "iron-plate" }
        local copper = { name = "copper-plate" }
        is_unfiltered_slot = function(slot)
            return slot.valid and slot.can_set_stack(iron) and slot.can_set_stack(copper)
        end
    end

    local function assert_row_index(row, index, function_name)
        assert(type(row) == 'number' and row >= 1 and row <= ROW_COUNT, function_name .. ': invalid row index')
        assert(type(index) == 'number' and index >= 1 and index <= QUICKBAR_SIZE, function_name .. ': invalid slot index')
    end

    local function find_empty_inventory_slot()
        local main_inventory = p.get_inventory(defines.inventory.player_main)
        if main_inventory == nil then
            main_inventory = p.get_inventory(defines.inventory.god_main)
            if main_inventory == nil then
                print([[potential error while swapping quickbar, cannot find a main inventory, neither player not god, skipping]])
                return nil
            end
        end

        for i = 1, #main_inventory do
            local slot = main_inventory[i]
            if slot.valid and not slot.valid_for_read and is_unfiltered_slot(slot) then
                return slot
            end
        end
        return nil
    end

    local function make_plan()
        local plan = {}
        local plan_finalizer = {}

        local function make_combined_plan()
            local p = {}
            for i = 1, #plan do p[i] = plan[i] end
            for i = 1, #plan_finalizer do p[i + #plan] = plan_finalizer[i] end
            return p
        end

        local plan_action = {}

        local function q_index(row, index) return (row - 1) * 10 + index end

        function plan_action.get_filter(row, index)
            assert_row_index(row, index, 'get_filter')
            return q.get_filter((row - 1) * 10 + index)
        end

        function plan_action.set_filter(row, index, value)
            assert_row_index(row, index, 'set_filter')
            assert(type(value) == 'string' or value == nil, 'set_filter: invalid filter value')
            plan[#plan + 1] = {
                function () q.set_filter(q_index(row, index), value) end,
                'set_filter',
                row, index, value or 'nil'
            }
        end

        function plan_action.get_slot(row, index)
            assert_row_index(row, index, 'get_slot')
            return q[q_index(row, index)]
        end

        function plan_action.is_slot_empty(row, index)
            assert_row_index(row, index, 'is_slot_empty')
            local slot = plan_action.get_slot(row, index)
            return not slot.valid_for_read or slot.count == 0;
        end

        function plan_action.move_stack(from, to)
            assert(type(from) == 'table' and from.valid, 'move_stack: from needs to be a valid ItemStack')
            assert(type(to) == 'table' and to.valid, 'move_stack: to needs to be a valid ItemStack')
            plan[#plan + 1] = {
                function ()
                    assert(to and to.valid and from and from.valid, 'move_stack: invalid slot')
                    if to.valid_for_read then
                        print('To contains: ' .. to.name)
                    end
                    assert(not to.valid_for_read or (to.valid_for_read and to.count == 0 and to.can_set_stack(from)), 'move_stack: target slot is not empty')
                    assert(from.valid_for_read and from.count > 0, 'move_stack: source slot is empty')

                    to.set_stack(from)
                    from.clear()
                end,
                'move_stack',
                tostring(from), tostring(to)
            }
        end

        function plan_action.finally(action_name, ...)
            assert(type(action_name) == 'string', 'finally: must provide a method name')
            local initial_length = #plan
            local res = { plan_action[action_name](...) }
            for i = initial_length + 1, #plan do
                plan_finalizer[#plan_finalizer + 1] = plan[i]
            end
            for i = #plan, initial_length + 1, -1 do
                plan[i] = nil
            end
            assert(#plan == initial_length)
        end

        function plan_action.execute()
            local p = make_combined_plan()
            plan, plan_finalizer = {}, {}
            for action_index, action in ipairs(p) do
                local success, error = pcall(action[1])
                if not success then
                    print('Error executing action ' .. tostring(action_index) .. ' of the plan')
                    print(error)
                    break
                end
            end
            return #p
        end

        return setmetatable({}, {
            __index = function(_, action)
                local handler = plan_action[action]
                assert(type(handler) == 'function', 'cannot find plan action: ' .. action)
                return handler
            end,
            __newindex = function () assert(false) end,
            __tostring = function ()
                local c = {}
                local p = make_combined_plan()
                for action_index, action in ipairs(p) do
                    c[#c + 1] = '['
                    c[#c + 1] = tostring(action_index)
                    c[#c + 1] = '] '
                    c[#c + 1] = action[2]
                    c[#c + 1] = '('
                    for j = 3, #action do
                        c[#c + 1] = tostring(action[j])
                        if j ~= #action then
                            c[#c + 1] = ', '
                        end
                    end
                    c[#c + 1] = ')\n'
                end
                return table.concat(c)
            end
        })
    end

    local function temporarily_clear_filter(actions, row, index)
        local filter = actions.get_filter(row, index)
        if filter ~= nil then
            actions.set_filter(row, index, nil)
            actions.finally('set_filter', row, index, filter)
        end
    end

    local function swap_quickbar(row_a, row_b)
        assert(type(row_a) == 'number' and row_a >= 1 and row_a <= ROW_COUNT)
        assert(type(row_b) == 'number' and row_b >= 1 and row_b <= ROW_COUNT)
        --[[ No swapping required if the a == b ]]
        if row_a == row_b then return end

        local actions = make_plan()

        --[[ Initially clear and finally swap all filters ]]
        for i = 1, QUICKBAR_SIZE do
            local filter_a, filter_b = actions.get_filter(row_a, i), actions.get_filter(row_b, i)
            if filter_a ~= nil then actions.set_filter(row_a, i, nil) actions.finally('set_filter', row_b, i, filter_a) end
            if filter_b ~= nil then actions.set_filter(row_b, i, nil) actions.finally('set_filter', row_a, i, filter_b) end
        end

        --[[
            Determine swapping mode, first valid option is taken:

            1) If there are empty slots in either quickbar currently being swapped,
            it'll swap those over directly. The first location that was swapped
            from is designated as the swapping slot for the rest.
            
            2) Use a free slot in any other quickbar.
            3) Use a free slot from the main inventory.
            4) Use the players' cursor.

            5) Print an error message to the player and don't execute the plan.
        ]]

        --[[ Indicates what slot is used for swapping items ]]
        local swap_slot = nil
        --[[ Memorizes which slots have already been swapped, filled in Step 1 ]]
        local swapped_slots = {}

        --[[
            Step 1. Check if there are any empty slots in either quickbar being
            swapped. If any are found, immediately swap them. Note that the swap
            is performed BEFORE we use the swap slot.
        ]]
        for i = 1, QUICKBAR_SIZE do
            local slot_a_empty, slot_b_empty = actions.is_slot_empty(row_a, i), actions.is_slot_empty(row_b, i)
            swapped_slots[i] = slot_a_empty or slot_b_empty

            if slot_a_empty then
                swap_slot = swap_slot or actions.get_slot(row_b, i)
                if not slot_b_empty then
                    actions.move_stack(actions.get_slot(row_b, i), actions.get_slot(row_a, i))
                end
            elseif slot_b_empty then
                swap_slot = swap_slot or actions.get_slot(row_a, i)
                actions.move_stack(actions.get_slot(row_a, i), actions.get_slot(row_b, i))
            end
        end

        --[[ Step 2. Check other quickbars ]]
        if not swap_slot then
            for row = 1, ROW_COUNT do
                if row ~= row_a and row ~= row_b then
                    for i = 1, QUICKBAR_SIZE do
                        if actions.is_slot_empty(row, i) then
                            local slot = actions.get_slot(row, i)
                            local filter = actions.get_filter(row, i)
                            if filter then
                                actions.set_filter(row, i, nil)
                                actions.finally('set_filter', row, i, filter)
                            end
                            swap_slot = slot
                        end
                    end
                end
                if swap_slot then
                    break
                end
            end
        end

        --[[ Step 3. Check main inventory ]]
        if not swap_slot then
            swap_slot = find_empty_inventory_slot()
        end

        --[[ Step 4. Check cursor ]]
        if not swap_slot then
            local c = p.character
            if p.cursor_stack and p.cursor_stack.valid and not p.cursor_stack.valid_for_read and is_unfiltered_slot(p.cursor_stack) then
                swap_slot = p.cursor_stack
            elseif c and c.cursor_stack and c.cursor_stack.valid and not c.cursor_stack.valid_for_read and is_unfiltered_slot(c.cursor_stack) then
                swap_slot = c.cursor_stack
            end
        end

        --[[ Error if there's no swap slot found ]]
        if not swap_slot then
            print('Cannot swap quickbar while all quickbars, your inventory and your cursor are full')
            return
        end

        --[[ Perform the swapping logic ]]
        for i = 1, QUICKBAR_SIZE do
            if not swapped_slots[i] then --[[ Skip already swapped slots ]]
                local slot_a, slot_b = actions.get_slot(row_a, i), actions.get_slot(row_b, i)
                actions.move_stack(slot_a, swap_slot)
                actions.move_stack(slot_b, slot_a)
                actions.move_stack(swap_slot, slot_b)
            end
        end

        --[[ print(tostring(actions)) ]]
        local execute_count = actions.execute()
        --[[ print(tostring(execute_count) .. ' actions executed') ]]
    end
    
    return ROW_COUNT, swap_quickbar
end

return load_swap_logic