pico-8 cartridge // http://www.pico-8.com
version 33
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
muted = true
timers = false
background_col = 1
foreground_col = 7
deaths = 0
time_start = 0
final_time = -1
num_keys = 0
num_coins = 0
sfx_frame = 0

-- global constants
grav = 0.15
k_left = 0
k_right = 1
k_jump = 2
k_jump_alt = 4
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

    -- check for win condition
    if (num_coins >= total_coins) then
        if (game_started) then
            delete_all_objects(nil)

            final_time = time() - time_start
            local final_deaths = deaths
            local win_menu = init_game_complete(final_time, final_deaths)

            add(objects, win_menu)
            game_started = false
        end
    end
end

function _draw()
    cls(background_col)
    draw_objects()
    -- if (not muted) then play_music() end 
    if (game_started) then 
        show_stats()
    end
end

function update_objects()
    for o in all(objects) do
        if(o.update ~= nil) then
            o.update(o)
        end
    end
end

function draw_objects()
    for o in all(objects) do
        if(o.draw ~= nil) then
            o.draw(o)
        end
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
    cat.jaccel = -1.6
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
    cat.can_move = false
    cat.button = nil
    cat.lever = nil

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

        if (this.on_ground and (btnp(k_jump) or btnp(k_jump_alt))) then
            this.dy = this.dy + this.jaccel
            this.on_ground = false
            -- play jump sound
            play_sfx(8)
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
        this.on_ground = false
        this.can_move = true
        
        local newx = this.pos.x + this.dx
        local xcol = collide(this, newx+this.box.x, this.pos.y+this.box.y, this.box.w, this.box.h, true)
        if (xcol ~= nil) then handle_collision(this, xcol, true) end
        if (this.can_move) then this.pos.x = this.pos.x + this.dx end

        this.can_move = true
        
        local newy = this.pos.y + this.dy
        local ycol = collide(this, this.pos.x+this.box.x, newy+this.box.y, this.box.w, this.box.h, false)
        if (ycol ~= nil) then handle_collision(this, ycol, false) end
        if (this.can_move) then this.pos.y = this.pos.y + this.dy end

        -- on button? check
        if (this.button ~= nil) and (xcol ~= this.button) and (ycol ~= this.button) then
            this.button.unpress(this.button)
            this.button = nil
        end

        -- on lever? check
        if (this.lever ~= nil) and (not collide_one(this, this.pos.x+this.box.x, this.pos.y+this.box.y, this.box.w, this.box.h, this.lever)) then
            this.lever = nil
        end

        -- death check
        if (this.dead) then
            deaths = deaths + 1
            destroy(this)
            return
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
            -- give the player a chance to react to the new room
            this.dy = this.saccel
        end

        if (tick) then
            animate(this)
        end
    end

    cat.draw = function(this)
        spr(this.spritenum, this.pos.x, this.pos.y, 1, 1, this.flip, false)
    end

    -- helper methods
    cat.handle_block = function(this, block, horiz)
        -- collided with a block, so stop moving
        this.can_move = false
        if (horiz) then
            if (this.pos.x < block.pos.x + block.box.x) then
                if ( (this.pos.y + this.box.y + this.box.h) - (block.pos.y + block.box.y) < 3 and
                     (this.pos.y + this.box.y + this.box.h) - (block.pos.y + block.box.y) > 0 and
                     (this.dy >= 0) ) then
                    -- just a small step up, go ahead and just move up
                    this.can_move = true
                    set_on_top(this, block)
                else
                    -- we are to the left
                    set_on_left(this, block)
                end
            else
                if ( (this.pos.y + this.box.y + this.box.h) - (block.pos.y + block.box.y) < 3 and
                     (this.pos.y + this.box.y + this.box.h) - (block.pos.y + block.box.y) > 0 and
                     (this.dy >= 0) ) then
                    -- just a small step up, go ahead and just move up
                    this.can_move = true
                    set_on_top(this, block)
                else
                    -- we are to the right
                    set_on_right(this, block)
                end
            end
        else
            if (this.pos.y < block.pos.y + block.box.y) then
                -- we are to the top
                this.on_ground = true
                set_on_top(this, block)
            else
                -- we are to the bottom
                set_on_bot(this, block)
            end
        end
    end

    cat.handle_switch_block = function(this, block, horiz)
        if (block.collideable) then
            this.handle_block(this, block, horiz)
        else
            this.can_move = true
        end
    end

    cat.handle_coin = function(this, coin, horiz)
        this.can_move = true
        coin.pick_up(coin)
    end

    cat.handle_key = function(this, key, horiz)
        this.can_move = true
        key.pick_up(key)
    end

    cat.handle_door = function(this, door, horiz)
        if (door.unlock(door)) then
            this.can_move = true
        else
            -- since we couldn't unlock the door, just treat it as a solid block
            this.handle_block(this, door, horiz)
        end
    end

    cat.handle_spike = function(this, spike, horiz)
        this.can_move = true
        this.dead = true
    end

    cat.handle_spring = function(this, spring, horiz)
        this.can_move = true
        set_on_top(this, spring)
        if (not horiz) then
            spring.press(spring)
            this.dy = this.saccel
            this.on_ground = false
        end
    end

    cat.handle_button = function(this, button, horiz)
        this.handle_block(this, button, horiz)
        this.button = button
        button.press(button)
    end

    cat.handle_lever = function(this, lever, horiz)
        if (this.lever == nil) then
            this.lever = lever
            if (lever.activated) then
                lever.unpress(lever)
            else
                lever.press(lever)
            end
        end
    end

    cat.handle_crate = function(this, crate, horiz)
        this.can_move = false
        if (horiz) then
            if (this.pos.x < crate.pos.x + crate.box.x) then
                local oldcratex = crate.pos.x
                local newcratex = crate.push(crate, this)
                if (oldcratex ~= newcratex) then
                    this.pos.x = newcratex - crate.box.x - crate.box.w - this.box.x
                else
                    this.handle_block(this, crate, horiz)
                end
            else
                local oldcratex = crate.pos.x
                local newcratex = crate.push(crate, this)
                if (oldcratex ~= newcratex) then
                    this.pos.x = newcratex + crate.box.x + crate.box.w + this.box.x
                else
                    this.handle_block(this, crate, horiz)
                end
            end
        else
            this.handle_block(this, crate, horiz)
        end
    end

    cat.handle_teleporter = function(this, teleporter, horiz)
        if (teleporter.active) then
            this.can_move = false
            teleporter.use(teleporter)
            this.pos.x = teleporter.connected_to.pos.x
            this.pos.y = teleporter.connected_to.pos.y
        end
    end

    return cat
end

function new_fake_cat(x, y)
    local cat = {}
    cat.pos = { x=x, y=y }
    cat.spritenum = 16
    cat.spritebase = 16
    cat.frames = 2
    cat.type = 'fake_cat'
    
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
    coin.bounce = false
    -- collisions
    coin.collideable = true
    coin.type = 'coin'

    coin.update = function(this)
        if tick then animate(this) end

        if (tick) then
            this.bounce = (not this.bounce)
        end
    end

    coin.draw = function(this)
        local delta = 0

        if (this.bounce) then
            delta = -1
        end

        spr(this.spritenum, this.pos.x, this.pos.y + delta)
    end

    coin.pick_up = function(this)
        num_coins = num_coins + 1
        -- play pickup sound
        play_sfx(10)
        del(objects, this)
    end

    return coin
end

function new_key(x, y)
    local key = {}
    -- movement
    key.pos = { x=x, y=y }
    key.box = { x=0, y=0, w=8, h=8 }
    -- animation
    key.spritenum = 51
    key.spritebase = 51
    key.frames = 1
    key.bounce = false
    -- collisions
    key.collideable = true
    key.type = 'key'

    key.update = function(this)
        if (tick) then
            this.bounce = (not this.bounce)
        end
    end

    key.draw = function(this)
        local delta = 0

        if (key.bounce) then
            delta = -1
        end

        spr(this.spritenum, this.pos.x, this.pos.y + delta)
    end


    key.pick_up = function(this)
        num_keys = num_keys + 1
        -- play pickup sound
        play_sfx(10)
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
        if (timers == true) then
            if (double_double_tick) then 
                this.toggle(this) 
                -- play activated sound
                play_sfx(9)
            end
        end
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

    return respawn
end

function new_teleporter(x, y, num)
    local teleporter = {}
    -- movement
    teleporter.pos = { x=x, y=y }
    teleporter.box = { x=0, y=0, w=8, h=8 }
    -- animation
    teleporter.spritenum = num
    teleporter.spritebase = num
    -- collisions
    teleporter.collideable = true
    teleporter.type = 'teleporter'
    -- don't allow multiple teleports without first waiting
    teleporter.active = true
    teleporter.wait_frames = 2
    teleporter.frame = 0
    -- where is our destination?
    teleporter.connected_to = nil

    teleporter.update = function(this)
        if (double_tick) and (this.frame > 0) then
            this.spritenum = 41
            this.frame = this.frame - 1
        elseif (double_tick) then
            this.spritenum = this.spritebase
            this.active = true
        end
    end

    teleporter.use = function(this)
        if (this.active) then
            -- play teleporter sound
            play_sfx(13)
            this.active = false
            this.frame = this.wait_frames
            this.spritenum = 41
            this.connected_to.use(this.connected_to)
        end
    end

    teleporter.draw = function(this)
        spr(this.spritenum, this.pos.x, this.pos.y)
    end 

    return teleporter
end

-->8
-- blocks
function new_spike(x, y, num)
    local spike = {}
    -- movement
    spike.pos = { x=x, y=y }
    spike.box = { x=0, y=0, w=8, h=8 } -- default, will change later
    -- animation
    spike.spritenum = num
    -- collisions
    spike.collideable = true
    spike.type = 'spike'

    -- change spike orientation based on spritenum
    if (num == 33) then -- spike up
        spike.box = { x=0, y=1, w=8, h=7 }
    elseif (num == 34) then -- spike down
        spike.box = { x=0, y=0, w=8, h=7 }
    elseif (num == 35) then -- spike right
        spike.box = { x=0, y=0, w=7, h=8 }
    else -- spike left
        spike.box = { x=1, y=0, w=7, h=8 }
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
        if (not this.pressed) then
            -- play spring sound
            play_sfx(11)
            this.pressed = true
        end
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
    button.type = 'button'

    button.update = function(this)
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

    button.press = function(this)
        if (not this.activated) then
            -- play activated sound
            play_sfx(9)
            this.activated = true
        end
    end

    button.unpress = function(this)
        if (this.activated) then
            -- play activated sound
            play_sfx(9)
            this.activated = false
        end
    end

    return button
end

function new_lever(x, y)
    local lever = {}
     -- movement
    lever.pos = { x=x, y=y }
    lever.box = { x=0, y=1, w=8, h=6 }
    -- animation
    lever.spritenum = 18
    lever.activated = false
    -- collisions
    lever.collideable = true
    lever.type = 'lever'

    lever.update = function(this)
        if (this.activated) then
            this.spritenum = 19
        elseif (not this.activated) then
            this.spritenum = 18
        end
    end

    lever.draw = function(this)
        spr(this.spritenum, this.pos.x, this.pos.y)
    end

    lever.press = function(this)
        if (not this.activated) then
            -- play activated sound
            play_sfx(9)
            this.activated = true
        end
    end

    lever.unpress = function(this)
        if (this.activated) then
            -- play activated sound
            play_sfx(9)
            this.activated = false
        end
    end

    return lever
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
    block.type = 'switch_block'
    block.default_on = start_on
    -- activation
    block.trigger = nil

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
        local col = collide(this, this.pos.x+this.box.x, this.pos.y+this.box.y, this.box.w, this.box.h)
        if (col ~= nil) then stop_activation = true end
        -- return to original state
        this.collideable = temp_collideable

        if (this.trigger == nil) then
            -- the trigger was deleted, don't try to update as we're about to be deleted as well
            return
        end

        -- if the trigger is a timer AND the timer setting is turned off, just always make this block active
        if (this.trigger.type == 'timer') and (timers == false) then
            -- switching state to on (started off)
            this.spritenum = 50
            this.collideable = true
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

function new_crate(x, y, cell)
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
    crate.saccel = -2.2
    -- animation
    crate.spritenum = cell
    -- collisions
    crate.collideable = true
    crate.type = 'crate'
    crate.on_ground = true
    crate.on_spike = false
    crate.can_move = false
    crate.button = nil

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

        this.on_ground = false
        this.can_move = true

        local xcol = collide(this, newx+this.box.x, this.pos.y+this.box.y, this.box.w, this.box.h, true)
        if (xcol ~= nil) then handle_collision(this, xcol, true) end
        if (this.can_move and (not this.on_spike)) then this.pos.x = this.pos.x + this.dx end

        this.can_move = true
        
        local ycol = collide(this, this.pos.x+this.box.x, newy+this.box.y, this.box.w, this.box.h, false)
        if (ycol ~= nil) then handle_collision(this, ycol, false) end
        if (this.can_move and (not this.on_spike)) then this.pos.y = this.pos.y + this.dy end

        -- on button? check
        if (this.button ~= nil) and (xcol ~= this.button) and (ycol ~= this.button) then
            this.button.unpress(this.button)
            this.button = nil
        end

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
    crate.handle_block = function(this, block, horiz)
        -- collided with a block, so stop moving
        this.can_move = false
        if (horiz) then
            if (this.pos.x < block.pos.x + block.box.x) then
                if ( (this.pos.y + this.box.y + this.box.h) - (block.pos.y + block.box.y) < 3 and
                     (this.pos.y + this.box.y + this.box.h) - (block.pos.y + block.box.y) > 0 ) then
                    -- just a small step up, go ahead and just move up
                    this.can_move = true
                    set_on_top(this, block)
                else
                    -- we are to the left
                    set_on_left(this, block)
                end
            else
                if ( (this.pos.y + this.box.y + this.box.h) - (block.pos.y + block.box.y) < 3 and
                     (this.pos.y + this.box.y + this.box.h) - (block.pos.y + block.box.y) > 0 ) then
                    -- just a small step up, go ahead and just move up
                    this.can_move = true
                    set_on_top(this, block)
                else
                    -- we are to the right
                    set_on_right(this, block)
                end
            end
        else
            if (this.pos.y < block.pos.y + block.box.y) then
                -- we are to the top
                this.on_ground = true
                set_on_top(this, block)
            else
                -- we are to the bottom
                set_on_bot(this, block)
            end
        end
    end

    crate.handle_switch_block = function(this, block, horiz)
        if (block.collideable) then
            this.handle_block(this, block, horiz)
        else
            this.can_move = true
        end
    end

    crate.handle_coin = function(this, coin, horiz)
        this.handle_block(this, coin, horiz)
    end

    crate.handle_key = function(this, key, horiz)
        this.handle_block(this, key, horiz)
    end

    crate.handle_door = function(this, door, horiz)
        this.handle_block(this, door, horiz)
    end

    crate.handle_spike = function(this, spike, horiz)
        this.handle_block(this, spike, horiz)
        this.on_spike = true
    end

    crate.handle_spring = function(this, spring, horiz)
        this.can_move = true
        set_on_top(this, spring)
        if (not horiz) then
            spring.press(spring)
            this.dy = this.saccel
            this.on_ground = false
        end
    end

    crate.handle_button = function(this, button, horiz)
        this.can_move = true
        this.handle_block(this, button, horiz)
        this.button = button
        button.press(button)
    end

    crate.handle_cat = function(this, cat, horiz)
        crate.handle_block(this, cat, horiz)
    end

    crate.handle_crate = function(this, crate, horiz)
        this.can_move = false
        if (horiz) then
            if (this.pos.x < crate.pos.x + crate.box.x) then
                local oldcratex = crate.pos.x
                local newcratex = crate.push(crate, this)
                if (oldcratex ~= newcratex) then
                    this.pos.x = newcratex - crate.box.x - crate.box.w - this.box.x
                else
                    this.handle_block(this, crate, horiz)
                end
            else
                local oldcratex = crate.pos.x
                local newcratex = crate.push(crate, this)
                if (oldcratex ~= newcratex) then
                    this.pos.x = newcratex + crate.box.x + crate.box.w + this.box.x
                else
                    this.handle_block(this, crate, horiz)
                end
            end
        else
            this.handle_block(this, crate, horiz)
        end
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
    door.type = 'door'

    door.draw = function(this)
        spr(this.spritenum, this.pos.x, this.pos.y)
    end

    door.unlock = function(this)
        if (num_keys > 0) then 
            num_keys = num_keys - 1
            -- play activated sound
            play_sfx(9)
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

    -- if this is a half block; adjust hitbox
    if (num == 72) or (num == 73) or (num == 74) or (num == 75) then
        block.box = { x=0, y=5, w=8, h=3 }
    end

    block.draw = function(this)
        spr(this.spritenum, this.pos.x, this.pos.y)
    end

    return block
end

-->8
-- menus

-- basic menu idea inspired by PixelCod: https://www.lexaloffle.com/bbs/?tid=27725
function init_main_menu()
    local main_menu = {}
    -- position
    main_menu.basex = 16
    main_menu.basey = 54
    -- option strings
    main_menu.options = { "start", "tutorial", "sound on", "hard mode", "palette", "quit" }
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

            if (new_opt.message == "sound on") and (muted == true) then
                new_opt.message = "sound off"
            end

            if (new_opt.message == "hard mode") and (timers == false) then
                new_opt.message = "normal mode"
            end

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
            -- play move cursor sound
            play_sfx(14)
            this.sel_num = this.sel_num - 1
            this.set_updating(this)
        end

        if ( (this.updating == false) and btn(k_down) and this.sel_num < #this.opts) then
            -- play move cursor sound
            play_sfx(14)
            this.sel_num = this.sel_num + 1
            this.set_updating(this)
        end

        if ( (this.ignore_input == false) and (this.updating == false) and btnp(k_confirm) ) then
            -- play activated sound
            play_sfx(9)
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
            -- play activated sound
            play_sfx(9)
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

function init_game_complete(t, d)
    local win_menu = {}
     -- position
    win_menu.basex = 74
    win_menu.basey = 110
    -- option objects
    win_menu.opts = {}
    -- ignore input for x frames
    win_menu.ignore_frames = 10
    win_menu.ignore_input = true
    -- values to remember
    win_menu.time = t
    win_menu.deaths = d
    -- fireworks
    win_menu.particles = {}

    win_menu.init = function (this)
        this.ignore_frames = 10
        this.ignore_input = true

        -- create a back button
        local new_opt = new_menu_option("main menu", this.basex, this.basey, 1)
        add(this.opts, new_opt)
    end

    win_menu.update = function(this)
        local opt = this.opts[1]
        opt.selected = true

        if (this.ignore_frames > 0) then
            this.ignore_frames = this.ignore_frames - 1
        else
            this.ignore_input = false
        end

        if ( (this.ignore_input == false) and (btn(k_confirm)) ) then
            -- play activated sound
            play_sfx(9)
            opt.action(opt)
        end

        opt.update(opt)

        -- fireworks
        this.update_particles(this)

        if (tick and double_double_tick) then
            this.boom(this, rnd(128), rnd(128))
        end
    end

    win_menu.draw = function(this)
        -- draw fireworks first so that they are behind everything else
        this.draw_particles(this)

        -- title
        print_title(48, 22)
        rect(45, 19, 81, 29, foreground_col)

        -- win_menu text
        print("congratulations!", 24, 41, foreground_col)
        
        -- final stats
        rect(21, 53, 104, 70, foreground_col)
        print(get_time_str(this.time, true), 24, 56, foreground_col)
        print("deaths: "..this.deaths, 24, 63, foreground_col)

        -- share instructions
        print("press f6 to take a", 24, 78, foreground_col)
        print("screenshot to share!", 24, 84, foreground_col)

        -- back button
        local opt = this.opts[1]
        opt.draw(opt)
    end

    ------------------------
    -- particles code from: https://www.lexaloffle.com/bbs/?pid=33755
    ------------------------

    win_menu.boom = function(this, _x,_y)
        -- create 100 particles at a location
        for i=0,100 do
            this.spawn_particle(this, _x,_y)
        end
    end
       
    win_menu.spawn_particle = function(this, _x,_y)
        -- create a new particle
        local new={}
        
        -- generate a random angle
        -- and speed
        local angle = rnd()
        local speed = 1+rnd(2)
        
        new.x=_x --set start position
        new.y=_y --set start position
        -- set velocity based on
        -- speed and angle
        new.dx=sin(angle)*speed
        new.dy=cos(angle)*speed
        
        --add a random starting age
        --to add more variety
        new.age=flr(rnd(25))
        
        --add the particle to the list
        add(this.particles,new)
    end
       
    win_menu.update_particles = function(this)
        --iterate trough all particles
        for p in all(this.particles) do
            --delete old particles
            --or if particle left 
            --the screen 
            if p.age > 80 
                or p.y > 128
                or p.y < 0
                or p.x > 128
                or p.x < 0
            then
                del(this.particles,p)
            else
                --move particle
                p.x+=p.dx
                p.y+=p.dy
                
                --age particle
                p.age+=1
                
                --add gravity
                p.dy+=0.15
            end
        end
    end
       
    win_menu.draw_particles = function(this) 
        --iterate trough all particles
        for p in all(this.particles) do
            pset(p.x,p.y,flr(rnd(3))+8)
        end
    end

    win_menu.init(win_menu)

    return win_menu
end

function new_menu_option(str, basex, basey, opt_num)
    local opt = {}
    -- position
    opt.pos = { x=basex, y=basey+(8*opt_num) }
    opt.base = { x=basex, y=basey+(8*opt_num) }
    opt.width = 45
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
            rectfill(this.pos.x-1, this.pos.y-1, this.pos.x + this.width, this.pos.y+5, foreground_col) -- this.pos.x + this.width
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

        if (this.message == "sound on") or (this.message == "sound off") then
            if (this.message == "sound on") then
                muted = true
                this.message = "sound off"
            else
                muted = false
                this.message = "sound on"
            end
        end

        if (this.message == "hard mode") or (this.message == "normal mode") then
            if (this.message == "hard mode") then
                timers = false
                this.message = "normal mode"
            else
                timers = true
                this.message = "hard mode"
            end
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

        if (this.message == "main menu") then
            -- restarts the cartridge; clears memory
            run()
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

function collide(ent, x, y, w, h, horiz)
    -- this will return the closest collision in the indicated direction with 'ent' in global 'objects'
    -- the 'ent' MUST resolve this collision
    local closest = {}
    local dists = {}
    for o in all(objects) do
        if ( ent ~= o and ent.collideable == true and o.collideable == true ) then
            -- if we have a collision, add it to the sorted list closest
            if ( collide_one(ent, x, y, w, h, o) ) then
                if (horiz) then
                    if (#closest == 0) then
                        add(closest, o)
                        add(dists, xdist)
                    else
                        local added = false
                        for idx, dist in pairs(dists) do
                            if (dist > xdist) then
                                add(closest, o, idx)
                                add(dists, xdist, idx)
                                added = true
                                break
                            end
                        end

                        if (not added) then
                            add(closest, o)
                            add(dists, xdist)
                        end
                    end
                else
                    if (#closest == 0) then
                        add(closest, o)
                        add(dists, ydist)
                    else
                        local added = false
                        for idx, dist in pairs(dists) do
                            if (dist > ydist) then
                                add(closest, o, idx)
                                add(dists, ydist, idx)
                                added = true
                                break
                            end
                        end

                        if (not added) then
                            add(closest, o)
                            add(dists, ydist)
                        end
                    end
                end
            end
        end
    end

    -- loop through the sorted closest list and determine which object should be returned
    local result = nil
    for obj in all(closest) do
        if (obj.type == 'teleporter') then
            if (obj.active) then
                result = obj
                break
            end
        elseif (obj.type == 'lever') then
            if (ent.lever == nil) then
                result = obj
                break
            end
        else
            result = obj
            break
        end
    end

    return result
end

function collide_one(ent, x, y, w, h, o)
    -- refer to: http://gamedev.docrobs.co.uk/first-steps-in-pico-8-hitting-things
    if ( ent ~= o and ent.collideable == true and o.collideable == true ) then
        local xdist = abs( (x + (w/2)) - (o.pos.x + o.box.x + (o.box.w/2)) )
        local xwidths = (w / 2) + (o.box.w / 2)
        local ydist = abs( (y + (h/2)) - (o.pos.y + o.box.y + (o.box.h/2)) )
        local ywidths = (h / 2) + (o.box.h / 2)

        -- if we have a collision, add it to the sorted list closest
        if ( (xdist < xwidths) and (ydist < ywidths) ) then
            return true
        end

        return false
    end
end

function handle_collision(obj1, obj2, horiz)
    -- call obj1's callback handler for obj2's type
    obj1["handle_"..obj2.type](obj1, obj2, horiz)
end

function destroy(ent)
    -- play destroy noise
    play_sfx(12)
    local explosion = new_explosion(ent.pos.x, ent.pos.y, false)
    add(objects, explosion)
    del(objects, ent)
end

function respawn()
    -- play respawn noise
    play_sfx(15)
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
    local telelist = { {}, {}, {}, {} }
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
            elseif (cell == 18) then -- lever
                obj = new_lever(pos.x, pos.y)
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
            elseif (cell == 52 or cell == 53) then -- door
                obj = new_door(pos.x, pos.y, cell)
            elseif (cell == 48 or cell == 11) then -- crate
                obj = new_crate(pos.x, pos.y, cell)
            elseif (cell >= 37 and cell <= 40) then -- teleporter
                obj = new_teleporter(pos.x, pos.y, cell)
                add(telelist[(cell-36)], obj)
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

    -- configure teleporters
    for l in all(telelist) do
        if( #l > 0 ) then
            l[1].connected_to = l[2]
            l[2].connected_to = l[1]
        end
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
    background_col = (background_col + 1) % 3
end

function show_stats()
    -- generate the stats    
    local time_passed = time() - time_start
    local time_str = get_time_str(time_passed)
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

function get_time_str(elapsed_time, is_victory_screen)
    local victory = is_victory_screen or false

    local minutes = left_pad(tostr(flr(elapsed_time / 60)), 2)
    local seconds = left_pad(tostr(flr(elapsed_time % 60)), 2)
    local fractional = right_pad(sub(tostr(elapsed_time - flr(elapsed_time)), 3, 4), 2)

    if (victory) then
        return "time:   " .. minutes .. ":" .. seconds .. "." .. fractional
    end

    return "time: " .. minutes .. ":" .. seconds .. "." .. fractional
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
    deaths = 0
    num_keys = 0
    num_coins = 0
    respawn()
    if (not muted) then music(0) end
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
    -- TODO: going to have to revisit this system
    if (half_tick) then
        -- each half-tick is 1/16th note
        sfx(0, 0, (sfx_frame % 32), 1)
        -- sfx(1, 1, (sfx_frame % 32), 1)
        sfx_frame = sfx_frame + 1
    end
end

function play_sfx(sfxn)
    if (not muted) then
        -- play sfx number sfxn, choose an available channel, start at note 0
        sfx(sfxn, -1, 0)
    end
end

__gfx__
70000007000000000000000000000000000000000000000000000000000000000000000000000000000000000700007000000000000000000000000000000000
07000070000000000000000000000000000000000000000000000000000000000000000000000000000000007770077700000000000000000000000000000000
0070070000088000000aa000000bb000000cc0000000000000000000000000000000000000000000000000007700007700000000000000000000000000000000
000770000088280000a9aa0000bb3b0000c1cc000000000000000000000000000000000000000000000000007000000700000000000000000000000000000000
000770000082880000aa9a0000b3bb0000cc1c000000000000000000000000000777777000000000000000007777777700000000000000000000000000000000
0070070000088000000aa000000bb000000cc0000077770000000000000000000070070000000000000000000707707000000000000000000000000000000000
07000070000000000000000000000000000000000700007007777770077777700007700000000000000000000777777000000000000000000000000000000000
70000007000000000000000000000000000000007777777777777777007777000070070000000000000000000700007000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000077000000000000000000700700707007007000000000000000000770077000000000000000000000000000000000
00007070000000000000000000000000000700770000000007070700070707000000000000000000000000007777700700000000000000000000000000000000
70070707000070700000077007700000000070700007000000070000000000000000000000000000000000007777770700000000000000000000000000000000
07770007777707070000077007700000700707000070700007707700770007707000007000000000000000000777777000000000000000000000000000000000
07007770070700070000070000700000777007000007000000070000000000000000000000000000000000000077770000000000000000000000000000000000
00777000007777700000700000070000700007000000000007070700070707000000000000000000000000000007700000000000000000000000000000000000
07000700007070000777777007777770077770000000000000000000700700707007007000000000000000000000000000000000000000000000000000000000
00000000007000707000700777700000000007770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00777700007000707000700700777700007777000077770000777700007777000077770000777700000000000000000000000000000000000000000000000000
00777700077007707707770700007777777700000700007007000070070000700700007007000070000000000000000000000000000000000000000000000000
00777700077707770707070700777000000777000707707007077070070700700707707007000070000000000000000000000000000000000000000000000000
00700000070707070777077777700000000007770700007007077070070000700707007007000070000000000000000000000000000000000000000000000000
00700000770777070770077000777700007777000700007007000070070000700700007007000070000000000000000000000000000000000000000000000000
00700000700070070070007000007777777700000077770000777700007777000077770000777700000000000000000000000000000000000000000000000000
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
70000000000000000000000707000000000000707000000000000007700000070777777777777777777777700777777000000000000000000000000000000000
70000000000000000000000707700000000007707000000000000007700000077000000000000000000000077000000700000000000000000000000000000000
70000000000000000000000700077777777770007000000000000007700000077000000000000000000000077000000700000000000000000000000000000000
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
04454545144545454545454545760046044545454545454545454545454545240445454545454545454545454545452404454545454545454545454545454524
04454545454525000006454545454524044545454545454545454545454545240445454545144545454545454545452446000006454545454545454545454524
46000000460000000000000000000046460000000000000000000000000000464600000000000000000000000000004646630000000000000000000000000046
46000000000046700000000000000046460000000000000000000000000000464600000000466200000000000000004646700000000000000000000000000046
46000000462100b400b084949494a446460000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000005205141424000000000046460000000000000000000300000000464600000000460000000000000000214605454545454544000000000000000046
46000000064545652323551616161625460000000000000000000000000000464600000000000000000000000000004646000000000414240000003500000046
46000010000400000000240000005246460000000000000000232323000000464600000000052400000035000004142546000000000000000000000000000046
46000000000000000000000000000046460000000000000000000000000000464600000000000000000000000000004646000004451600164545452600000046
46000034451616161616164545451425460000000000000000000000000000464600000000061645454516454516162546000000000000007000000000000046
46000000000000000000000000000046460000000000000000000066454545162600000000000000000000000000000626000046000036000000000000700046
46000000000000000000000000420525460000000000000000000000000000464600000000000000000000000000004646000000003445454545440000000046
46000000000000000000000000000006260000000000000000000023000000000000000000000000000000000000000000027046000000000000044545454525
46700000000000003444000002420525460000000000000000000000000000464610000000000000000000000000624605440000000000000000000000000046
46000000000000000000000000000000000000000000000000000023000033042400000000000000000000000000000414454525000034454545260000000046
05761300000034440000000034451625461000000000000000000000000000062600000013000000131313000000004646100000350000000000000000000046
46001000000000000000000000000002020000000000000000044545454545254670000000000000000000000002704646100046230000000000000000000046
46121212121200000000000000006306164576000000000000000000000000000000000000000000000000000004451616454545164545454545440000000046
46003500000035000000000035000004240000000000000000750000000000460514240000000000000000000066452546000006454544000000000000000006
16454545454544000000007000000000000023005600000000000000000000000000000000000000000000003465000000000000000000000000000000003425
4600461212124612121212124612124605240000000000700023102100000046050025b400000003000000b40043104646700000000000000035000000000000
0000000000000000000004640000330000002300500000b40000000200b400042402000000000000003500000043000000000200000000000000003500000046
46000545454516454545454516454526061645454545454545454545240000460616161645454545454545164545452606454545454545454516454545454545
45454545454545240000051645454545454545454545451645454545451645260645240000044545451645454545454545454545454545454545451624000046
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
46000645454545454545454545454524044545454545454545454545260000460445454545454545454545454545454545454545454545454545454545454545
45454545454545260000054545454524044545454545454545454545454545240445250000064545454545454545452404454545454545454545454526000046
46000000000000000000000000000046466300000000000000000000000070464600000000000000000000000000020000000000000000005000000000000000
00000000020000000070460000008246460000000003000000000000000000464600467000000000000000000000634646630000000000000000000002007046
46000000000000000000000000000046460000000000344545454545454545254662000000000000000000344545451414454545454545454545454545454514
24232334454545451445260000001046460000000023000000000000000000061645164545454545440000000000004646000000520033000000003445454525
46000000000000000000000010000046460000007000000000000000000000464615000000150000001500000000004646000000000000000300000000000046
46000000000000004600000000007246460000000000000000000000000000000000000000000000000000000052004646000034454545240000000000000046
46020000001500000000000000000046460000344544000000000010000000464612121212121212121212121212124646000000000000002300000000000046
4670000000000052460000000000004646100084a4008494a4218494a40000000000000010000000000070000000004646000000000000460000000000000046
05440000000000000000000035000006260000000000001300003445440000460545454545454545451445454545452546000000000000001300000000000046
05454545454545452600000000000006164545161645161616451616164545141444000015000034454545454545452546000000000000360013130000000046
46000000000000000070000046000000000200000000000000000000000070464662000000000000003600000000004646000000000000002300000000000046
46820000000000000000000000000000000000000000000000000000000000464600000000000000000000000000004646000000000000000000000000000046
46000000000000000056000006454514144400000000000000000000003445254600000035000070000000000000004646000000000000000000000000000046
46000000000000000000000000000000000000000000000000000000000000464600000000000000000000000000524646520000000000000000000000001046
46000000000000000000000000000046460000000000000013131300000000460545454500454545452400000000000626000000000000000000000000000006
16454544000034454400720034454514240000000000000000000000000000062600000000000000000000000000004605454545454400000023230000002346
46000000000000000000000000000046460000000034440000000000000000464600000075000000000644000000000000000000000000000000000000000000
00000023000000000000000000000046460002000000000000000000000000000000000000000023230000232300004646000000000000000000000000000046
46121212121212121212121212121246461212121212121212121212121212464610000053000000000000000070000000000000023512121212123510000000
000021230000000000007000000052464670849494a412849494a400000000000002000035121212121212121212124646121212121212121212121212121246
06454545454545454545454545454526064545454545454545454545454545260645454545454545454545454545454545454545451645454545451645454545
45454545454545454545454545454526064516161616451616161645454545454545454516454545454545454545452606454545454545454545454545454526
__label__
11177777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777111
17711111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111771
17111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171
71111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111117
71111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111117
71111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111117
71111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111117
71111111777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777711111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111177777777111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111177111117111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111171711117111111111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111111111171171117171711111111111111111111111111111111111111111111111111111111111171111117
71111117111111111111111111111111111111111777777171117117717177771111111111111111111111111111111117777771111111111111111171111117
71111117111111111111111111111111111111117111111771111717711171711111111111111111111111111111111171111117111111111111111171111117
71111117111111111111111111111111111111117111111771111177177777111111111111111111111111111111111171111117111111111111111171111117
71111117111111111111111111111111111111117111111777777777111717111111111111111111111111111111111171111117111111111111111171111117
71111111777777777777777777777777777777771111111177777777777777777777777777777777777777777777777711111111777777777777777711111117
71111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111117
71111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111117
71111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111117
71111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111117
17111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111171
17711111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111771
11177777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777777111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111117771111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111771777177717111771117717771777111111111111111111111111111111111177117717771771117711111111177711171777177711111111111111111
11117111717171117711717171117171171111111111111111111111111111111111711171711711717171111711111171711711117111711111111111111111
11117771777177117111717171117771171111111111111111111111111111111111711171711711717177711111111171711711177177711111111111111111
11111171711171117771717171117171171111111111111111111111111111111111711171711711717111711711111171711711117171111111111111111111
11117711711177711111777117717171171111111111111111111111111111111111177177117771717177111111111177717111777177711111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11117771777177717771111111117771777111117771777111117771777111111111717177717171177111111111111111111111777111111111111111111111
11111711171177717111171111117171717117111171117111111171717111111111717171117171711117111111117711117171717111111111111111111111
11111711171171717711111111117171717111111771777111117771717111111111771177117771777111111117777171111711717111111111111111111111
11111711171171717111171111117171717117111171711111117111717111111111717171111171117117111111711771111711717111111111111111111111
11111711777171717771111111117771777111117771777117117771777111111111717177717771771111111111111111117171777111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11117771177117717771111111117171111111111111111111111111111111111111771177717771777171711771111111117771111111111111111111111111
11117171717171717771171111117171111111111111111111111111111111111111717171117171171171717111171111117171111111111111111111111111
11117711717171717171111111117771111111111111111111111111111111111111717177117771171177717771111111117171111111111111111111111111
11117171717171717171171111111171111111111111111111111111111111111111717171117171171171711171171111117171111111111111111111111111
11117171771177117171111111111171111111111111111111111111111111111111777177717171171171717711111111117771111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111

__map__
4054545454545454545454545454544240545454545454545454545454545442405454545454545454545454545454424054545454545454545454545454544240545454545454545454545454545442405454545454545454545454545454424054545454544154545454545454544240545454544154545441545454545442
6400000000000000000000000000006464360000000000000000000000000064640000000000000000000000000000606228000000000000000000000000006464360000000000000000000000000060622500000000000000000000000000606200000000006400000000000000006464010000005700000057000000000064
6400000000000000000000000000006464000000000000000000000000000064640000000000000000000000000001000000000000000000000000000000006464000000000000000000000000000000002000000000000000000000000000000000000000006400000000000000006464000000000000000000000000000064
6400000000000000000000000000006464000000000000000000000000000064640000000000000000000000000043414144000000000000000000000000006464000000270000000000000000004041415454440000003131313100000043414142000000256400000000000000006464070000000000070000000700000064
6400000000000000000000000000006464000000000000000000000000000060615442000000000000000000000000646400000000000000000000000000006062000000000000000000000000075052640000000000000000000000000033645052000000076400000000000000006061545454545454545454545444000064
6400000000000000000000000000006464000000000000000000000000000000000060440000000000000000000000646400000000434400000000000000000000000000000000000031310000666152640000000000004054545454545454525061545454546200010000000000000000000000000000002600000000000064
6400000000000000000000000000006464000000000000000000000000000100000030200000530000000000000000646400000000000000434400000020004041440000650032320000000000000064640000000000006400000000000000646400000000000000000000000000120000200000000000000000000000000764
6400000000000000000000000000006464000000000000000000000000004341415454415454620000434400000033646400000000000000000000004067326464000000000000000000000000000064640000000000006400000000000000646400000000000000000031000043544141440000405454544154545441545452
6400000000000000000000000000006464000000000000000000006500000064640000640000000000000000000040526400000000000000000000076400006464000000000000000000000001000064505442000000006400000000000001646400000000000000000025000000006464000000570000005700000057000064
6400000000010000000000530000006062000000000000003100000000000064640000570000000000000000004000525054546700000000004054545600006464000000000000000000003232000064640057250000005700000000000000646400000000000000000000000000006464000000000000000000000000000064
6420000000530000000007640000000000200000005321212121212121212164640000350053000000000000400000526412003500000000076428003200016464270000002000000000212121212164641235000000003200000031000000646400000000002000212121212121216464260000000007000000070000000064
6054545454615454545454615454545454545454546154545454545454545462640040545461545454545454616161626054545454545454546154545454546260545454545442000040545454545461615454545454545454545454545454626042000040545454545454545454546260545454545454545454545442000064
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4054545454545454545454545454544240545454545454545454545454545442640060545454545454545454545454424054545454545454545454545454544240545454545452000060545454545442405454545454545454545454545454424062000060545441545454545454544240545454545454545454544162000064
6400003000000000000000000000006464360000000000000000000000000064640000000000000000000000000024646400000000000000000000000000006464000000000064070000000000002664643600000000000000000000000025646400000000000064000000000000286464000000000000000000006427000764
6400003200000000000000000000006062000000000000000000000000000064642000000000000000000000000024646400000000000000000000000000006464000000000060545454545454545452640000000000000000000000000000646400000000000064000000000000006464000000000000000000006054545452
6400000000000000000000000000002000000000000000000000000000000064504142000053000053000053000024646400000000000000000000000000006464000000000000000000000000000064640000000000000000000000000000646400000000001264000000000000016464000027000000510000000000000064
6401000000000000000000000000004041440000000100000000000000003364500052212164212164212164000024646400010000000000000000000000256464000000000000000000000000000064642501000000000000000000000000606154543232545462000000006654546162000000000000000053000000000064
5042000000000000000043440000006464000000435444000000000000435452500000545461545461545456000024556154440000650000000000665454546162000000000000001200000000002664640031000000000000000000000000000000000000000000000000003200000000000000000000000060545444000064
5052212121214042000000000007006464000000000000000032320000000064500052000000000000000000000000000020000000000000070000340000000000200000435454545454545454545452640000003200000000000000000000000000000000000000000000003200200000200000000000000000000000000064
5061545454546156000000004341415264000000000000434400000000000060616152000000000000000000435454414154545454545454545454545454544141420000000000000000000000310064640000000000310000000000000000000000000000000000000000665454544141440000000001000000000000000764
6400002200000022000000000050615264000000003232000000000000000020000063000000000000006500320000646400000000000000000000000000006450520700000000000000000000310164640000000000000032000000000020000000000000000000000000000000006464000000435454544400004054545452
6405000000000000000007000057006464000043440000000000000000004041420030000000000065000000320000646425000000000000000000000000006450004142000000000000000000665452640000000000000000003131004041414200000000000000005300000000006464000000000000000000006400000064
504141414200404141414600003400646407000000000000000000000040005264054041414200000000000032000164640700000000000000000000000033645000000042000000000000070032336464212121212121212121212121500052644b0030000000004b5042000000286464000000000000000000076400000064
6061616156215561616161545467006460545454545454545454545454616162605461616161545454545454545454626054545454545454545454545454546260616161615442000040545454545462605454545454545454545454546161626061545454545454616161545454546264000040545454545454546154545462
__sfx__
011c00000c073344001b6533e4000c0000c0731b6532d4000c073344001b6533e4000c0000c0731b6532d4000c073344001b6533e4000c0000c0731b6532d4000c073344001b6533e4000c0000c0731b6532d400
011c00000c3200c3200c3200c3200c3200c3200c3200c3200b3200b3200b3200b3200b3200b3200b3200b32009320093200932009320093200932009320093200532005320053200532009320093200932009320
011c00002431237312343123731224312373123431237312233123731234312373122331237312343123731224312393123531239312243123931235312393123231239312353123931232312393123531232312
091c0000242200000028220000002422024220242202422524220000002822000000232202322023220232252d2200000029220000002d2202d2202d2202d2252d2200000029220000002d220000002622026225
091c00002422024220242202422528220282202b2202b2202322023220232202322528220282202b2202b22021220212202122021225242202422029220292201d2201d2201d2201d22526220262202122021220
091c0000242202d2202b2002b22028220000002622026220232202322023220232201f2201f2201f2201f220242202d220000002b220292200000028220282202422024220242202422026220262202622026220
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
050100001235313353143531435315353163531635317353173531735318353193431b3431d3431e3432034323343243432434300303003030030300303003030030300303003030030300303003030030300303
01020000206701b6700d67003670136700b6700467000670000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010200002836028360283602836028360283603936039360393603936039360393603930039300393003930000300003000030000300003000030000300003000030000300003000030000300003000030000300
05010000045700557006570095700b5700e57010570115701257012570135701257011570105700f5700e5700d5700d5700d5700d5700f57011570145701a5701c57008500085002350000500005000050000500
0102000034670336703267031670306702d6602a6602565023650206601e6601c6701b6501a6501865015640146401465014660146601365012640106500d6400000000000000000000000000000000000000000
09010000330723307233072330723307233072300622e0622e0622b0622706224052220521f0521b07218072130720f0720707200002000020000200002000020000200002000020000200002000020000200002
010100001806018060180601806018060180601806018060180601806018060180600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010600000e0500e0500e0501305013060130601707017070170701707017075000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
00 02414344
00 00010244
01 00010203
00 00010203
00 00010204
00 00010204
02 00010205
00 40414245

