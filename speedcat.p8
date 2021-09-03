pico-8 cartridge // http://www.pico-8.com
version 29
__lua__
-- speedcat 
-- game by fletch
-- tab 0 has global values, game logic in subsequent tabs

-- global counters
frame = 0
room_num = 0
room_respawn = { x=0, y=0 }
objects = {}
room_states = {}
half_tick = false
tick = false
double_tick = false
double_double_tick = false
game_started = false
background_col = 1
foreground_col = 7
deaths = 0
time_start = 0
num_keys = 0
num_coins = 0
sfx_frame = 0

-- global constants
grav = 0.15
k_left = 0
k_right = 1
k_jump = 2
k_up = 2
k_down = 3
k_confirm = 4
anim_frame = 16
empty_cell = 0
room_bounds = { x=0, y=0, w=128, h=96}
total_coins = 32

-->8
-- lifecycle
function _init()
    local menu = init_main_menu()
    add(objects, menu)
end

function _update60()
    frame = frame + 1
    if (frame % anim_frame == 0) then tick = true else tick = false end
    if (frame % (anim_frame / 2) == 0) then half_tick = true else half_tick = false end
    if (frame % (anim_frame * 2) == 0) then double_tick = true else double_tick = false end
    if (frame % (anim_frame * 4) == 0) then double_double_tick = true else double_double_tick = false end
    update_objects()
end

function _draw()
    cls(background_col)
    draw_objects()
    if (game_started) then 
        show_stats() 
        -- play_music() 
    end
end

function update_objects()
    for o in all(objects) do
        o.update(o)
    end
end

function draw_objects()
    for o in all(objects) do
        o.draw(o)
    end
end

-->8
-- entities
function new_cat(x, y)
    local cat = {}
    -- movement
    cat.pos = { x=x, y=y }
    cat.box = { x=0, y=2, w=8, h=6 }
    cat.dx = 0
    cat.dy = 0
    -- physics
    cat.accel = 0.06
    cat.deccel = 0.1
    cat.jaccel = -2
    cat.saccel = -2.5
    cat.maxhvel = 1
    cat.minhvel = -1
    cat.maxvvel = 6
    cat.minvvel = -6
    -- animation
    cat.flip = false
    cat.spritenum = 16
    cat.spritebase = 16
    cat.frames = 2
    cat.dead = false
    -- collisions
    cat.collideable = true
    cat.type = 'cat'
    cat.on_ground = false

    cat.update = function(this)
        -- movement + physics
        if (btn(k_left)) and (this.dx > 0) then
            -- if we are travelling right at the time, slow down faster
            this.dx = this.dx - this.deccel
        elseif (btn(k_left)) then
            -- if we are travelling left already, speed up at normal speed
            this.dx = this.dx - this.accel
            this.flip = true
        end

        if (btn(k_right)) and (this.dx < 0) then
            -- if we are travelling left at the time, slow down faster
            this.dx = this.dx + this.deccel
        elseif (btn(k_right)) then
            -- if we are travelling right already, speed up at normal speed
            this.dx = this.dx + this.accel
            this.flip = false
        end

        if (not btn(k_left) and not btn(k_right)) then
            if this.dx > this.deccel then
                this.dx = this.dx - this.deccel
            elseif this.dx < -(this.deccel) then
                this.dx = this.dx + this.deccel
            else
                this.dx = 0
            end
        end

        if (this.on_ground and btn(k_jump)) then
            this.dy = this.dy + this.jaccel
            this.on_ground = false
        else
            this.dy = this.dy + grav
        end

        if (this.dx > this.maxhvel) then
            this.dx = this.maxhvel
        elseif (this.dx < this.minhvel) then
            this.dx = this.minhvel
        end

        if (this.dy > this.maxvvel) then
            this.dy = this.maxvvel
        elseif (this.dy < this.minvvel) then
            this.dy = this.minvvel
        end

        -- collisions
        local newx = this.pos.x + this.dx
        local newy = this.pos.y + this.dy

        local xcollisions = collide(this, newx+this.box.x, this.pos.y+this.box.y, this.box.w, this.box.h)
        this.handle_collisions(this, xcollisions, true, newx)

        if (not this.dead) then 
            local ycollisions = collide(this, this.pos.x+this.box.x, newy+this.box.y, this.box.w, this.box.h)
            this.handle_collisions(this, ycollisions, false, newy) 
        end

        if (abs(this.dx) < this.accel) then
            this.dx = 0
            -- round, but do so differently if facing left or right (reduces jitter bug)
            if (this.flip) then this.pos.x = flr(this.pos.x)
            else this.pos.x = flr(this.pos.x + 0.5) end
        end

        if (abs(this.dy) < this.accel) then
            this.dy = 0
            this.pos.y = flr(this.pos.y)
        end

        -- room logic
        if (this.pos.x >= room_bounds.x + room_bounds.w) then
            update_room_right()
            this.pos.x = room_bounds.x
            this.pos.y = this.pos.y - this.dy
        elseif (this.pos.x + this.box.x + this.box.w - 1 < room_bounds.x) then
            update_room_left()
            this.pos.x = room_bounds.x + room_bounds.w - this.box.w
            this.pos.y = this.pos.y - this.dy
        elseif (this.pos.y >= room_bounds.y + room_bounds.h) then
            update_room_down()
            this.pos.y = room_bounds.y
            this.pos.x = this.pos.x - this.dx
        elseif (this.pos.y + this.box.y + this.box.h - 1 < room_bounds.y) then
            update_room_up()
            this.pos.y = room_bounds.y + room_bounds.h - this.box.h
            this.pos.x = this.pos.x - this.dx
        end

        if (tick) then
            animate(this)
        end
    end

    cat.draw = function(this)
        spr(this.spritenum, this.pos.x, this.pos.y, 1, 1, this.flip, false)
    end

    -- helper methods
    cat.handle_collisions = function(this, col_list, horiz, newcoord)
        local can_move = true
        for col in all(col_list) do
            if (col.type == 'block') then
                -- collided with a block, so stop this action
                can_move = false
                if (horiz and this.pos.x < col.pos.x + col.box.x) then
                    -- we are to the left
                    if (col.push ~= nil) then
                        colx = col.push(col, this)
                        this.pos.x = colx - col.box.x - col.box.w - this.box.x
                    elseif (col.unlock ~= nil) then
                        local unlocked = col.unlock(col)
                        if (unlocked) then can_move = true else set_on_left(this, col) end
                    elseif (col.box.h > 2) then
                        set_on_left(this, col)
                    else
                        set_on_top(this, col)
                        this.pos.x = newcoord
                    end
                elseif (horiz) then
                    -- we are to the right
                    if (col.push ~= nil) then 
                        colx = col.push(col, this)
                        this.pos.x = colx + col.box.x + col.box.w + this.box.x
                    elseif (col.unlock ~= nil) then
                        local unlocked = col.unlock(col)
                        if (unlocked) then can_move = true else set_on_right(this, col) end
                    elseif (col.box.h > 2) then
                        set_on_right(this, col)
                    else
                        set_on_top(this, col)
                        this.pos.x = newcoord
                    end
                elseif (not horiz and this.pos.y < col.pos.y + col.box.y) then
                    -- we are to the top
                    set_on_top(this, col)
                    this.on_ground = true
                elseif (not horiz) then
                    -- we are to the bottom
                    set_on_bot(this, col)
                    this.on_ground = false
                end
            elseif (col.type == 'spring' and not horiz) then
                col.press(col)
                set_on_top(this, col)
                this.dy = this.saccel
                this.on_ground = false
                return 
            elseif (col.type == 'spike') then
                if (horiz) then this.pos.x = newcoord else this.pos.y = newcoord end
                deaths = deaths + 1
                this.dead = true
                destroy(this)
                return
            elseif (col.type == 'coin' or col.type == 'key') then
                col.pick_up(col)
            else
                -- should not be reached
            end
        end

        if (can_move and horiz) then this.pos.x = newcoord
        elseif (can_move and not horiz) then this.pos.y = newcoord end
    end

    return cat
end

function new_fake_cat(x, y)
    local cat = {}
    cat.pos = { x=x, y=y }
    cat.spritenum = 16
    cat.spritebase = 16
    cat.frames = 2
    
    cat.update = function(this)
        if (tick) then
            animate(this)
        end
    end

    cat.draw = function(this)
        spr(this.spritenum, this.pos.x, this.pos.y)
    end

    return cat
end

function new_coin(x, y)
    local coin = {}
    -- movement
    coin.pos = { x=x, y=y }
    coin.box = { x=2, y=2, w=4, h=4 }
    -- animation
    coin.spritenum = 1
    coin.spritebase = 1
    coin.frames = 4
    -- collisions
    coin.collideable = true
    coin.type = 'coin'

    coin.update = function(this)
        if tick then animate(this) end
        if (tick and double_tick) then
            this.pos.y = this.pos.y - 1
        elseif (tick) then
            this.pos.y = this.pos.y + 1
        end
    end

    coin.draw = function(this)
        spr(this.spritenum, this.pos.x, this.pos.y)
    end

    coin.pick_up = function(this)
        num_coins = num_coins + 1
        del(objects, this)
    end

    return coin
end

function new_key(x, y)
    local key = {}
    -- movement
    key.pos = { x=x, y=y }
    key.box = { x=1, y=3, w=6, h=3 }
    -- animation
    key.spritenum = 51
    key.spritebase = 51
    key.frames = 1
    -- collisions
    key.collideable = true
    key.type = 'key'

    key.update = function(this)
        if (tick and double_tick) then
            this.pos.y = this.pos.y + 1
        elseif (tick) then
            this.pos.y = this.pos.y - 1
        end
    end

    key.draw = function(this)
        spr(this.spritenum, this.pos.x, this.pos.y)
    end

    key.pick_up = function(this)
        num_keys = num_keys + 1
        del(objects, this)
    end    

    return key
end

function new_explosion(x, y, r)
    local explosion = {}
    -- movement
    explosion.pos = { x=x, y=y }
    explosion.box = { x=0, y=0, w=8, h=8 }
    -- animation
    explosion.spritenum = 21
    explosion.spritebase = 21
    explosion.frames = 4
    -- collisions
    explosion.collideable = false
    explosion.type = 'explosion'
    -- logic
    explosion.respawn = r

    explosion.update = function(this)
        if (half_tick and (this.spritenum == (this.spritebase + this.frames - 1))) then
            if (this.respawn) then
                local cat = new_cat(this.pos.x, this.pos.y)
                add(objects, cat)
                del(objects, this)
            else -- not a respawn, but a death
                respawn()
                del(objects, this)
            end
        elseif (half_tick) then
            animate(this)
        end
    end

    explosion.draw = function(this)
        spr(this.spritenum, this.pos.x, this.pos.y)
    end

    return explosion
end

function new_timed_trigger()
    local timer = {}
    timer.activated = false
    timer.collideable = false
    timer.type = 'timer'

    timer.update = function(this)
        if (double_double_tick) then this.toggle(this) end
    end

    timer.draw = function(this)
        -- empty
    end

    timer.toggle = function(this)
        if (this.activated) then this.activated = false else this.activated = true end
    end

    return timer
end

function new_respawn(x, y)
    local respawn = {}
    -- movement
    respawn.pos = { x=x, y=y }
    respawn.box = { x=0, y=0, w=8, h=8 }
    -- animation
    respawn.spritenum = 32
    -- collisions
    respawn.collideable = false
    respawn.type = 'respawn'

    respawn.update = function(this)
        -- empty
    end

    respawn.draw = function(this)
        -- empty
    end

    return respawn
end

-->8
-- blocks
function new_spike(x, y, num)
    local spike = {}
    -- movement
    spike.pos = { x=x, y=y }
    spike.box = { x=0, y=0, w=8, h=8 }
    -- animation
    spike.spritenum = num
    -- collisions
    spike.collideable = true
    spike.type = 'spike'

    spike.update = function(this)
        -- empty
    end

    spike.draw = function(this)
        spr(this.spritenum, this.pos.x, this.pos.y)
    end

    return spike
end

function new_spring(x, y)
    local spring = {}
    -- movement
    spring.pos = { x=x, y=y }
    spring.box = { x=0, y=6, w=6, h=2 }
    -- animation
    spring.spritenum = 7
    spring.pressed = false
    spring.reset = false
    spring.reset_count = 8
    -- collisions
    spring.collideable = true
    spring.type = 'spring'

    spring.update = function(this)
        if (this.pressed and not this.reset) then
            this.spritenum = 8
            this.reset = true
        elseif (this.reset) then
            this.reset_count = this.reset_count - 1
            if (this.reset_count == 0) then
                this.spritenum = 7
                this.pressed = false
                this.reset = false
                this.reset_count = 8
            end
        end
    end

    spring.draw = function(this)
        spr(this.spritenum, this.pos.x, this.pos.y)
    end

    spring.press = function(this)
        this.pressed = true
    end

    return spring
end

function new_button(x, y)
    local button = {}
     -- movement
    button.pos = { x=x, y=y }
    button.box = { x=0, y=6, w=8, h=2 }
    -- animation
    button.spritenum = 5
    button.activated = false
    button.reset = false
    -- collisions
    button.collideable = true
    button.type = 'block'

    button.update = function(this)
        -- look for a collision with 'cat' or 'crate' on top of the button
        local bcollisions = collide(this, this.pos.x + this.box.x, this.pos.y + this.box.y - 1, this.box.w, this.box.h)

        this.handle_collisions(this, bcollisions)

        if (this.activated and not this.reset) then
            this.spritenum = 6
            this.reset = true
        elseif (this.reset and not this.activated) then
                this.spritenum = 5
                this.activated = false
                this.reset = false
        end
    end

    button.draw = function(this)
        spr(this.spritenum, this.pos.x, this.pos.y)
    end

    -- helper functions
    button.handle_collisions = function(this, col_list)
        local has_pressed = false
        for col in all(col_list) do
            if (col.type == 'cat' or col.type == 'block') then
                has_pressed = true
                set_on_top(col, this)
                col.on_ground = true
            end
        end

        if (has_pressed) then this.activated = true else this.activated = false end
    end

    return button
end

function new_switch_block(x, y, start_on)
    local block = {}
    -- movement
    block.pos = { x=x, y=y }
    block.box = { x=0, y=0, w=8, h=8 }
    -- animation
    block.spritenum = 49
    -- collisions
    block.collideable = false
    block.type = 'block'
    block.default_on = start_on
    -- activation
    block.trigger = nil
    block.num_collisions = 0

    block.init = function(this)
        if (this.default_on) then
            this.spritenum = 50
            this.collideable = true
        else
            this.spritenum = 49
            this.collideable = false
        end
    end

    block.update = function(this)
        -- grab the current value of collideable
        local temp_collideable = this.collideable
        local stop_activation = false
        this.collideable = true
        -- look for potential collisions
        local collisions = collide(this, this.pos.x+this.box.x, this.pos.y+this.box.y, this.box.w, this.box.h)
        if (#collisions > 0) then stop_activation = true end
        this.num_collisions = #collisions
        -- return to original state
        this.collideable = temp_collideable

        if (not this.trigger) then
            -- the trigger was deleted, don't try to update as we're about to be deleted as well
            return
        end

        if (this.trigger.activated and this.default_on) then
            -- switching state to off (started on)
            this.spritenum = 49
            this.collideable = false
        elseif (this.trigger.activated and not this.default_on and not stop_activation) then
            -- switching state to on (started off)
            this.spritenum = 50
            this.collideable = true
        elseif (not this.trigger.activated and this.default_on and not stop_activation) then
            -- switching state to on (started on)
            this.spritenum = 50
            this.collideable = true
        elseif (not this.trigger.activated and not this.default_on) then
            -- switching state to off (started off)
            this.spritenum = 49
            this.collideable = false
        end
    end

    block.draw = function(this)
        spr(this.spritenum, this.pos.x, this.pos.y)
    end

    block.init(block)

    return block
end

function new_crate(x, y)
    local crate = {}
    -- movement
    crate.pos = { x=x, y=y }
    crate.box = { x=0, y=0, w=8, h=8 }
    crate.dx = 0
    crate.dy = 0
    -- physics
    crate.friction = 0.03
    crate.maxhvel = 0.5
    crate.minhvel = -0.5
    crate.maxvvel = 4
    crate.minvvel = -3.5
    -- animation
    crate.spritenum = 48
    -- collisions
    crate.collideable = true
    crate.type = 'block'
    crate.on_ground = true

    crate.update = function(this)
        this.dy = this.dy + grav
        if (this.dx > 0) then this.dx = this.dx - this.friction
        elseif (this.dx < 0) then this.dx = this.dx + this.friction end

        if (this.dx > this.maxhvel) then
            this.dx = this.maxhvel
        elseif (this.dx < this.minhvel) then
            this.dx = this.minhvel
        end

        if (this.dy > this.maxvvel) then
            this.dy = this.maxvvel
        elseif (this.dy < this.minvvel) then
            this.dy = this.minvvel
        end

        local newx = this.pos.x + this.dx
        local newy = this.pos.y + this.dy

        local xcollisions = collide(this, newx+this.box.x, this.pos.y+this.box.y, this.box.w, this.box.h)
        this.handle_collisions(this, xcollisions, true, newx)

        local ycollisions = collide(this, this.pos.x+this.box.x, newy+this.box.y, this.box.w, this.box.h)
        this.handle_collisions(this, ycollisions, false, newy)

        if (abs(this.dx) < 0.1) then
            this.dx = 0
            if (this.dx < 0) then this.pos.x = flr(this.pos.x)
            elseif (this.dx > 0) then this.pos.x = flr(this.pos.x + 0.5) end
        end

        if (abs(this.dy) < 0.1) then
            this.dy = 0
            this.pos.y = flr(this.pos.y)
        end
    end

    crate.draw = function(this)
        spr(this.spritenum, this.pos.x, this.pos.y)
    end

    -- helper methods
    crate.handle_collisions = function(this, col_list, horiz, newcoord)
        local can_move = true
        for col in all(col_list) do
            if (col.type == 'block' or col.type == 'spike') then
                -- collided with a block, so stop this action
                can_move = false
                if (horiz and this.pos.x < col.pos.x + col.box.x) then
                    -- we are to the left
                    if (col.box.h > 2) then
                        set_on_left(this, col)
                    else
                        set_on_top(this, col)
                        this.pos.x = newcoord
                    end
                elseif (horiz) then
                    -- we are to the right
                    if (col.box.h > 2) then
                        set_on_right(this, col)
                    else
                        set_on_top(this, col)
                        this.pos.x = newcoord
                    end
                elseif (not horiz and this.pos.y < col.pos.y + col.box.y) then
                    -- we are to the top
                    set_on_top(this, col)
                elseif (not horiz) then
                    -- we are to the bottom
                    set_on_bot(this, col)
                end
            else
                -- should not be reached
                can_move = false
            end
        end

        if (can_move and horiz) then this.pos.x = newcoord
        elseif (can_move and not horiz) then this.pos.y = newcoord end
    end

    crate.push = function(this, ent)
        this.dx = this.dx + ent.dx
        this.update(this)

        return this.pos.x
    end

    return crate
end

function new_door(x, y, num)
    local door = {}
    door.pos = { x=x, y=y }
    door.box = { x=0, y=0, w=8, h=8 }
    door.spritenum = num
    door.collideable = true
    door.type = 'block'

    door.update = function(this)
        -- empty
    end

    door.draw = function(this)
        spr(this.spritenum, this.pos.x, this.pos.y)
    end

    door.unlock = function(this)
        if (num_keys > 0) then 
            num_keys = num_keys - 1
            del(objects, this)
            return true
        end
        return false
    end

    return door
end

function new_block(x, y, num)
    local block = {}
    -- movement
    block.pos = { x=x, y=y }
    block.box = { x=0, y=0, w=8, h=8 }
    -- animation
    block.spritenum = num
    -- collisions
    block.collideable = true
    block.type = 'block'

    block.update = function(this)
        -- empty
    end

    block.draw = function(this)
        spr(this.spritenum, this.pos.x, this.pos.y)
    end

    return block
end

-->8
-- main menu

-- basic menu idea inspired by PixelCod: https://www.lexaloffle.com/bbs/?tid=27725
function init_main_menu()
    local main_menu = {}
    -- position
    main_menu.basex = 16
    main_menu.basey = 54
    -- option strings
    main_menu.options = { "start", "tutorial", "palette", "quit" }
    -- option objects
    main_menu.opts = {}
    main_menu.selection = nil
    main_menu.sel_num = 1
    -- animation
    main_menu.updating = false
    main_menu.wait_timer = 0
    main_menu.wait_frames = 7
    -- ignore input for x frames
    main_menu.ignore_frames = 10
    main_menu.ignore_input = true

    main_menu.init = function(this)
        this.ignore_frames = 10
        this.ignore_input = true
    
        -- get the menu options ready
        local opt_count = 0
        for opt in all(this.options) do
            new_opt = new_menu_option(opt, this.basex, this.basey, opt_count)
            add(this.opts, new_opt)
            opt_count = opt_count + 1
        end

        this.selection = this.opts[this.sel_num]

        -- add the fake cat
        local fake_cat = new_fake_cat(60, 32)
        add(objects, fake_cat)
    end

    main_menu.set_updating = function(this)
        this.updating = true
        this.wait_timer = this.wait_timer + 1
    end

    main_menu.update = function(this)
        if (this.ignore_frames > 0) then
            this.ignore_frames = this.ignore_frames - 1
        else
            this.ignore_input = false
        end

        -- determine selection & highlight
        if ( (this.updating == false) and btn(k_up) and this.sel_num > 1) then
            this.sel_num = this.sel_num - 1
            this.set_updating(this)
        end

        if ( (this.updating == false) and btn(k_down) and this.sel_num < #this.opts) then
            this.sel_num = this.sel_num + 1
            this.set_updating(this)
        end

        if ( (this.ignore_input == false) and (this.updating == false) and btnp(k_confirm) ) then
            this.selection.action(this.selection)
            this.set_updating(this)
        end

        if (this.wait_timer % this.wait_frames == 0) then
            this.updating = false
        end

        if (this.updating == true) then
            this.set_updating(this)
        end

        this.selection = this.opts[this.sel_num]

        for opt in all(this.opts) do
            if (this.selection == opt) then
                opt.selected = true
            else
                opt.selected = false
            end
            opt.update(opt)
        end
    end

    main_menu.draw = function(this)
        -- add the title
        print_title(48, 24)
        rect(45, 21, 81, 31, foreground_col)

        -- draw the options
        for opt in all(this.opts) do
            opt.draw(opt)
        end
    end

    main_menu.init(main_menu)

    return main_menu
end

function init_tutorial()
    local tutorial = {}
     -- position
    tutorial.basex = 74
    tutorial.basey = 110
    -- option objects
    tutorial.opts = {}
    -- ignore input for x frames
    tutorial.ignore_frames = 10
    tutorial.ignore_input = true

    tutorial.init = function (this)
        this.ignore_frames = 10
        this.ignore_input = true

        -- create a back button
        local new_opt = new_menu_option("back", this.basex, this.basey, 1)
        add(this.opts, new_opt)

        -- add tutorial objects to screen
        local cat = new_fake_cat(8, 16)
        add(objects, cat)

        local coin = new_coin(8, 32)
        add(objects, coin)
    end

    tutorial.update = function(this)
        local opt = this.opts[1]
        opt.selected = true

        if (this.ignore_frames > 0) then
            this.ignore_frames = this.ignore_frames - 1
        else
            this.ignore_input = false
        end

        if ( (this.ignore_input == false) and (btn(k_confirm)) ) then
            opt.action(opt)
        end

        opt.update(opt)
    end

    tutorial.draw = function(this)
        -- title
        print_title(48, 6)
        rect(45, 3, 81, 13, foreground_col)

        -- tutorial text
        print("this is you. you're a cat.", 24, 19, foreground_col)

        print("this is a coin. collect", 24, 31, foreground_col)
        print("all 32 of them to win.", 24, 37, foreground_col)

        spr(54, 8, 50) -- timer icon
        print("you will be timed.", 24, 48, foreground_col)
        print("be fast.", 24, 55, foreground_col)

        spr(55, 9, 68) -- skull icon
        print("you might die.", 24, 66, foreground_col)
        print("you will respawn.", 24, 73, foreground_col)

        spr(56, 8, 86) -- thumbs up icon
        print("learn the rest as you", 24, 84, foreground_col)
        print("go. good luck!", 24, 91, foreground_col)

        -- back button
        local opt = this.opts[1]
        opt.draw(opt)
    end

    tutorial.init(tutorial)

    return tutorial
end

function new_menu_option(str, basex, basey, opt_num)
    local opt = {}
    -- position
    opt.pos = { x=basex, y=basey+(8*opt_num) }
    opt.base = { x=basex, y=basey+(8*opt_num) }
    opt.width = 40
    -- animation
    opt.vel = 1
    opt.maxoffset = 9
    opt.message = str
    opt.selected = false

    opt.update = function(this)
        if (this.selected and this.pos.x < this.base.x + this.maxoffset) then
            this.pos.x = this.pos.x + this.vel
        elseif (this.selected) then
            this.pos.x = this.base.x + this.maxoffset
        else
            this.pos.x = this.base.x
        end
    end

    opt.draw = function(this)
        if (this.selected) then
            rectfill(this.pos.x-1, this.pos.y-1, this.pos.x + this.width, this.pos.y+5, foreground_col)
            print(this.message, this.pos.x, this.pos.y, background_col)
        else
            print(this.message, this.pos.x, this.pos.y, foreground_col)
        end
    end

    opt.action = function(this)
        if (this.message == "start") then
            start_game()
        end

        if (this.message == "tutorial") then
            delete_all_objects()
            local tutorial = init_tutorial()
            add(objects, tutorial)
        end

        if (this.message == "palette") then
            change_background()
        end

        if (this.message == "quit") then
            cls(0)
            stop()
        end

        if (this.message == "back") then
            delete_all_objects()
            local menu = init_main_menu()
            add(objects, menu)
        end
    end

    return opt
end

-->8
-- entity helpers
function animate(obj)
    obj.spritenum = obj.spritenum + 1
    if (obj.spritenum == obj.spritebase + obj.frames) then
        obj.spritenum = obj.spritebase
    end
end

function collide(ent, x, y, w, h)
    -- refer to: http://gamedev.docrobs.co.uk/first-steps-in-pico-8-hitting-things
    -- this will return a list of all collisions with 'ent' in global 'objects'
    -- the 'ent' MUST resolve all of these collisions
    local collisions = {}
    for o in all(objects) do
        if (ent ~= o and ent.collideable == true and o.collideable == true ) then
            local xdist = abs( (x + (w/2)) - (o.pos.x + o.box.x + (o.box.w/2)) )
            local xwidths = (w / 2) + (o.box.w / 2)
            local ydist = abs( (y + (h/2)) - (o.pos.y + o.box.y + (o.box.h/2)) )
            local ywidths = (h / 2) + (o.box.h / 2)

            if ( (xdist < xwidths) and (ydist < ywidths) ) then
                add(collisions, o)
            end
        end
    end
    return collisions
end

function destroy(ent)
    local explosion = new_explosion(ent.pos.x, ent.pos.y, false)
    add(objects, explosion)
    del(objects, ent)
end

function respawn()
    local explosion = new_explosion(room_respawn.x, room_respawn.y, true)
    add(objects, explosion)
end

function delete_all_objects(keep_entity)
    for o in all(objects) do
        if (o ~= keep_entity) then del(objects, o) end
    end
end

function set_on_left(ent1, ent2)
    ent1.pos.x = ent2.pos.x + ent2.box.x - ent1.box.w - ent1.box.x
    ent1.dx = 0
end

function set_on_right(ent1, ent2)
    ent1.pos.x = ent2.pos.x + ent1.box.w
    ent1.dx = 0
end

function set_on_top(ent1, ent2)  
    ent1.pos.y = ent2.pos.y + ent2.box.y - ent1.box.h - ent1.box.y
    ent1.dy = 0
end

function set_on_bot(ent1, ent2)
    ent1.pos.y = ent2.pos.y + ent1.box.h
    ent1.dy = 0
end

-->8
-- room functions
function init_all_rooms()
    for nroom = 0,31 do
        local room = init_room(nroom)
        add(room_states, room)
    end
end

function init_room(num)
    -- rooms are 16x16 cells
    -- the map size is 128x64 cells
    -- thus we have 4 total rows, 8 total columns
    local col = (num % 8) * 16
    local row = flr(num / 8) * 16
    local switch = nil
    local switchable = {}
    local room_objects = {}
    for cell_x = col,col+15 do
        for cell_y = row,row+15 do
            local cell = mget(cell_x, cell_y)
            local pos = { x = (cell_x - col)*8, y = (cell_y - row)*8 }
            local obj = nil
            if (cell == 32) then -- spawn point
                obj = new_respawn(pos.x, pos.y)
            elseif (cell == 1) then -- coin
                obj = new_coin(pos.x, pos.y)
            elseif (cell == 51) then -- key
                obj = new_key(pos.x, pos.y)
            elseif (cell == 33 or cell == 34 or
                    cell == 35 or cell == 36) then -- spikes
                obj = new_spike(pos.x, pos.y, cell)
            elseif (cell == 7) then -- spring
                obj = new_spring(pos.x, pos.y)
            elseif (cell == 5) then -- button
                obj = new_button(pos.x, pos.y)
                switch = obj
            elseif (cell == 54) then -- timer switch
                obj = new_timed_trigger()
                switch = obj
            elseif (cell == 49) then -- switch block (start off)
                obj = new_switch_block(pos.x, pos.y, false)
                add(switchable, obj)
            elseif (cell == 50) then -- switch block (start on)
                obj = new_switch_block(pos.x, pos.y, true)
                add(switchable, obj)
            elseif (cell == 52 or cell == 53) then -- create a door
                obj = new_door(pos.x, pos.y, cell)
            elseif (cell == 48) then -- crate
                obj = new_crate(pos.x, pos.y)
            elseif (cell ~= empty_cell) then -- block
                obj = new_block(pos.x, pos.y, cell)
            end

            -- add to tracked objects
            if (obj ~= nil) then add(room_objects, obj) end
        end
    end

    -- configure switches and switchables
    for s in all(switchable) do
        s.trigger = switch
    end

    return room_objects
end

function init_first_room()
    delete_all_objects(nil)

    room_num = 0 -- change this to set the first spawn room

    for o in all(room_states[room_num + 1]) do
        add(objects, o)
        if(o.type == 'respawn') then
            room_respawn.x = o.pos.x
            room_respawn.y = o.pos.y
        end
    end
end

function update_room(cur_room_num, new_room_num)
    -- erase the stored room state
    for o in all(room_states[cur_room_num + 1]) do
        del(room_states[cur_room_num + 1], o)
    end

    local player = nil
    -- record the current state of the room
    for o in all(objects) do
        if (o.type ~= 'cat') then
            add(room_states[cur_room_num + 1], o)
        else
            player = o
        end
    end

    -- delete the current room state
    delete_all_objects(player)

    -- load the new room state
    for o in all(room_states[new_room_num + 1]) do
        add(objects, o)
        if (o.type == 'respawn') then
            room_respawn.x = o.pos.x
            room_respawn.y = o.pos.y
        end
    end

    -- update the room num
    room_num = new_room_num
end

function update_room_left()
    update_room(room_num, room_num - 1)
end

function update_room_right()
    update_room(room_num, room_num + 1)
end

function update_room_up()
    update_room(room_num, room_num - 8)
end

function update_room_down()
    update_room(room_num, room_num + 8)
end

-->8
-- misc helpers

function change_background()
    background_col = (background_col + 1) % 4
end

function show_stats()
    -- generate the stats    
    local time_passed = time() - time_start
    local minutes = left_pad(tostr(flr(time_passed / 60)), 2)
    local seconds = left_pad(tostr(flr(time_passed % 60)), 2)
    local fractional = right_pad(sub(tostr(time_passed - flr(time_passed)), 3, 4), 2)

    local time_str = "time: " .. minutes .. ":" .. seconds .. "." .. fractional
    local room_str = "room: " .. (room_num + 1)

    local coin_str = "coins: " .. num_coins .. "/" .. total_coins
    local key_str = "keys:   X" .. num_keys
    local death_str = "deaths: " .. deaths

    -- print the left stats
    print_title(4, 101)
    print(time_str, 4, 109, foreground_col)
    print(room_str, 4, 117, foreground_col)

    -- print the right stats
    print(coin_str, 68, 101, foreground_col)
    print(key_str, 68, 109, foreground_col)
    spr(51, 90, 108)
    print(death_str, 68, 117, foreground_col)
end

function left_pad(str, pnum)
    if (#str < pnum) then
        str = "0" .. str
        return left_pad(str, pnum)
    else
        return str
    end
end

function right_pad(str, pnum)
    if (#str < pnum) then
        str = str .. "0"
        return right_pad(str, pnum)
    else
        return str
    end
end

function start_game()
    init_all_rooms()
    init_first_room()
    game_started = true
    time_start = time()
    frame = 0
    respawn()
end

function print_title(x, y)
    local title = "speedcat"
    local letters = split(title, "")
    local lidx = 0
    for l in all(letters) do
        if (lidx == flr((frame % 64) / 4)) then
            print(l, x + (lidx * 4), y - 1, foreground_col)
        else 
            print(l, x + (lidx * 4), y, foreground_col)
        end
        lidx = lidx + 1
    end
end

function play_music()
    if (half_tick) then
        -- each half-tick is 1/16th note
        sfx(0, 0, (sfx_frame % 32), 1)
        sfx(1, 1, (sfx_frame % 32), 1)
        sfx_frame = sfx_frame + 1
    end
end

__gfx__
70000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
07000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0070070000088000000aa000000bb000000cc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000770000088280000a9aa0000bb3b0000c1cc000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000770000082880000aa9a0000b3bb0000cc1c000000000000000000000000000777777000000000000000000000000000000000000000000000000000000000
0070070000088000000aa000000bb000000cc0000077770000000000000000000070070000000000000000000000000000000000000000000000000000000000
07000070000000000000000000000000000000000700007007777770077777700007700000000000000000000000000000000000000000000000000000000000
70000007000000000000000000000000000000007777777777777777007777000070070000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000077000000000000000000700700707007007000000000000000000000000000000000000000000000000000000000
00007070000000000000000000000000000700770000000007070700070707000000000000000000000000000000000000000000000000000000000000000000
70070707000070700000000000000000000070700007000000070000000000000000000000000000000000000000000000000000000000000000000000000000
07770007777707070000000000000000700707000070700007707700770007707000007000000000000000000000000000000000000000000000000000000000
07007770070700070000000000000000777007000007000000070000000000000000000000000000000000000000000000000000000000000000000000000000
00777000007777700000000000000000700007000000000007070700070707000000000000000000000000000000000000000000000000000000000000000000
07000700007070000000000000000000077770000000000000000000700700707007007000000000000000000000000000000000000000000000000000000000
00000000007000707000700777700000000007770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00777700007000707000700700777700007777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00777700077007707707770700007777777700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00777700077707770707070700777000000777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700000070707070777077777700000000007770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700000770777070770077000777700007777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700000700070070070007000007777777700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000700070070070007077777000000777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
77777777070707070777777000000000770000000000007700777700000000000000000000000000000000000000000000000000000000000000000000000000
77000007700000007000000700000000770007000070007707000070077777000000006000000000000000000000000000000000000000000000000000000000
70700007000000077000000700007700770070700707007770007007777777700600067600000000000000000000000000000000000000000000000000000000
70070007700000007000000707777070770077700777007770007007700700706760677600000000000000000000000000000000000000000000000000000000
70007007000000077000000700700770770770777707707770777007777777706776776000000000000000000000000000000000000000000000000000000000
70000707700000007000000700000000770770777707707770000007077777000677760000000000000000000000000000000000000000000000000000000000
70000077000000077000000700000000770077700777007707000070007070000067600000000000000000000000000000000000000000000000000000000000
77777777707070700777777000000000770000000000007700777700000000000006000000000000000000000000000000000000000000000000000000000000
00077777777777777777700000077777777770000777777777777770077777700000000000000000000000000000000000000000000000000000000000000000
07700000000000000000077007700000000007707000000000000007700000070000000000000000000000000000000000000000000000000000000000000000
07000000000000000000007007000000000000707000000000000007700000070000000000000000000000000000000000000000000000000000000000000000
70000000000000000000000770000000000000077000000000000007700000070000000000000000000000000000000000000000000000000000000000000000
70000000000000000000000770000000000000077000000000000007700000070000000000000000000000000000000000000000000000000000000000000000
70000000000000000000000707000000000000707000000000000007700000070000000000000000000000000000000000000000000000000000000000000000
70000000000000000000000707700000000007707000000000000007700000070000000000000000000000000000000000000000000000000000000000000000
70000000000000000000000700077777777770007000000000000007700000070000000000000000000000000000000000000000000000000000000000000000
70000000000770000000000700077000777777777000000000000007700000070000000000000000000000000000000000000000000000000000000000000000
70000000077007700000000707700770000000007000000000000007700000070000000000000000000000000000000000000000000000000000000000000000
70000000070000700000000707000070000000007000000000000007700000070000000000000000000000000000000000000000000000000000000000000000
70000000700000070000000770000007000000007000000000000007700000070000000000000000000000000000000000000000000000000000000000000000
70000000700000070000000770000007000000007000000000000007700000070000000000000000000000000000000000000000000000000000000000000000
70000000070000700000000770000007000000007000000000000007700000070000000000000000000000000000000000000000000000000000000000000000
70000000077007700000000770000007000000007000000000000007700000070000000000000000000000000000000000000000000000000000000000000000
70000000000770000000000770000007777777770777777777777770077777700000000000000000000000000000000000000000000000000000000000000000
70000000000000000000000770000007700000070777777007777777777777700000000000000000000000000000000000000000000000000000000000000000
70000000000000000000000770000007700000077000000770000000000000070000000000000000000000000000000000000000000000000000000000000000
70000000000000000000000770000007700000077000000770000000000000070000000000000000000000000000000000000000000000000000000000000000
70000000000000000000000770000007700000077000000770000000000000070000000000000000000000000000000000000000000000000000000000000000
70000000000000000000000770000007700000077000000770000000000000070000000000000000000000000000000000000000000000000000000000000000
07000000000000000000007007000070700000077000000770000000000000070000000000000000000000000000000000000000000000000000000000000000
07700000000000000000077007700770700000077000000770000000000000070000000000000000000000000000000000000000000000000000000000000000
00077777777777777777700000077000700000070777777007777777777777700000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04454545454545454545454545760046044545454545454545454545454545240445454545454545454545454545452404454545454545454545454545454524
04454545454545454545454545454524044545454545454545454545454545240445454545454545454545454545452404454545454545454545454545454524
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
06454545454545454545454545454526064545454545454545454545454545260645454545454545454545454545452606454545454545454545454545454526
06454545454545454545454545454526064545454545454545454545454545260645454545454545454545454545452606454545454545454545454545454526
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04454545454545454545454545454524044545454545454545454545454545240445454545454545454545454545452404454545454545454545454545454524
04454545454545454545454545454524044545454545454545454545454545240445454545454545454545454545452404454545454545454545454545454524
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
06454545454545454545454545454526064545454545454545454545454545260645454545454545454545454545452606454545454545454545454545454526
06454545454545454545454545454526064545454545454545454545454545260645454545454545454545454545452606454545454545454545454545454526
__map__
4054545454545454545454545454544141545454545454545454545454545442405454545454545454545454545454424054545454545454545454545454544240545454545454545454545454545442405454545454545454545454545454424054545454545454545454545454544240545454545454545454545454545442
6400000000000000000000000000006464360000000000000000000000000064640000000000000000000000000000646400000000000000000000000000006464000000000000000000000000000064640000000000000000000000000000646400000000000000000000000000006464000000000000000000000000000064
6400000000000000000000000000006464000000000000000000000000000064640000000000000000000000000000646400000000000000000000000000006464000000000000000000000000000064640000000000000000000000000000646400000000000000000000000000006464000000000000000000000000000064
6400000000000000000000000000006464000000000000000000000000000064640100000000000000000000000000646400000000000000000000000000006464000000000000000000000000000064640000000000000000000000000000646400000000000000000000000000006464000000000000000000000000000064
6400000000000000000000000000006464000000000000000000000000000060615442000000000000000000000000646400000000000000000000000000006464000000000000000000000000000064640000000000000000000000000000646400000000000000000000000000006464000000000000000000000000000064
6400000000000000000000000000006464000000000000000000000000000000000060440000000000000000000000646400000000000000000000000000006464000000000000000000000000000064640000000000000000000000000000646400000000000000000000000000006464000000000000000000000000000064
6400000000000000000000000000006464000000000000000000000000000100000030200000530000000000000000646400000000000000000000000000006464000000000000000000000000000064640000000000000000000000000000646400000000000000000000000000006464000000000000000000000000000064
6400000000000000000000000000006464000000000000000000000000004341415454415454620000434400000033646400000000000000000000000000006464000000000000000000000000000064640000000000000000000000000000646400000000000000000000000000006464000000000000000000000000000064
6400000000000000000000000000006062000000000000000000003100000064640000640000000000000000000047646400000000000000000000000000006464000000000000000000000000000064640000000000000000000000000000646400000000000000000000000000006464000000000000000000000000000064
6400000000010000000000530000000000000000000000003200000000000064640000570000000000000000006557646400000000000000000000000000006464000000000000000000000000000064640000000000000000000000000000646400000000000000000000000000006464000000000000000000000000000064
6420000000530000000007640000000000200000005321212121212121212164640000350053000000000000665467646400000000000000000000000000006464000000000000000000000000000064640000000000000000000000000000646400000000000000000000000000006464000000000000000000000000000064
6054545454615454545454615454545454545454546154545454545454545462640040545461545454545454545454626054545454545454545454545454546260545454545454545454545454545462605454545454545454545454545454626054545454545454545454545454546260545454545454545454545454545462
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4054545454545454545454545454544240545454545454545454545454545442640060545454545454545454545454424054545454545454545454545454544240545454545454545454545454545442405454545454545454545454545454424054545454545454545454545454544240545454545454545454545454545442
6400300030000000000000000000006464360000000000000000000000000064640000000000000000000000000024646400000000000000000000000000006464000000000000000000000000000064640000000000000000000000000000646400000000000000000000000000006464000000000000000000000000000064
6400320032000000000000000000006062000000000000000000000000000064642000000000000000000000000024646400000000000000000000000000006464000000000000000000000000000064640000000000000000000000000000646400000000000000000000000000006464000000000000000000000000000064
6400000000000000000000000000002000000000000000000000000066545452004142000053000053000053000024646400000000000000000000000000006464000000000000000000000000000064640000000000000000000000000000646400000000000000000000000000006464000000000000000000000000000064
6401000000000000000000000000004041440000010000000000000032000064484852212164212164212164000024646400000000000000000000000000006464000000000000000000000000000064640000000000000000000000000000646400000000000000000000000000006464000000000000000000000000000064
5042000000000000000000000007006464000065656500000000000032003364484800545461545461545456000024556100000000000000000000000000006464000000000000000000000000000064640000000000000000000000000000646400000000000000000000000000006464000000000000000000000000000064
5052212121214042000051000065006464000000000000003232000043545452484852000000000000000000000000000000000000000000000000000000006464000000000000000000000000000064640000000000000000000000000000646400000000000000000000000000006464000000000000000000000000000064
5061545454546156000000000000076464000000000000310000000000000060616152000000000000000000435454414100000000000000000000000000006464000000000000000000000000000064640000000000000000000000000000646400000000000000000000000000006464000000000000000000000000000064
6400002200000022000000000040545264000000323232000000000000000020000063000000000000005100320000646400000000000000000000000000006464000000000000000000000000000064640000000000000000000000000000646400000000000000000000000000006464000000000000000000000000000064
6405000000000000000053000057006464003131000000000000000000004041420030000000000051000000320000646400000000000000000000000000006464000000000000000000000000000064640000000000000000000000000000646400000000000000000000000000006464000000000000000000000000000064
5041414142004041414152070034006464070000000000000000000000400052640545414146000000000000320001646400000000000000000000000000006464000000000000000000000000000064640000000000000000000000000000646400000000000000000000000000006464000000000000000000000000000064
6061616156215561616161545467006460545454545454545454545454616162605461616161545454545454545454626054545454545454545454545454546260545454545454545454545454545462605454545454545454545454545454626054545454545454545454545454546260545454545454545454545454545462
__sfx__
011000000c100002001b60000000103001b600000001b6000c100000001b60000000103001b600000001b6000c100000001b60000000103001b600000001b6000c100000001b60000000103001b600000001b600
011000001b0001b0001b0001d0001d0001f0002200022000220001d0001b0001600016000160001d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
