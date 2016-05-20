--[[

Copyright (C) 2016 Ivan Baidakou

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

]]--

local inspect = require('inspect')
local _ = require ("moses")

local Image = require 'polkovodets.utils.Image'
local Region = require 'polkovodets.utils.Region'

local RadialMenu = {}
RadialMenu.__index = RadialMenu

function RadialMenu.create(engine, tile_context)
  assert(tile_context.tile)
  assert(tile_context.x)
  assert(tile_context.y)
  local o = {
    engine = engine,
    -- mimic window properties
    properties  = {
      floating = false,
    },
    tile_context = tile_context,
    drawing      = {
      ui_update_listener = nil,
      context            = nil,
      fn                 = nil,
      mouse_click        = nil,
      objects             = {},
    }
  }
  return setmetatable(o, RadialMenu)
end

function RadialMenu:_hex_actions()
  local engine = self.engine
  local state = engine.state
  local theme = engine.gear:get("theme")
  local my_unit = state:get_selected_unit()
  local tile = self.tile_context.tile
  local tile_units = tile:get_all_units(function() return true end)
  local current_layer = state:get_active_layer()
  local current_player = state:get_current_player()

  local list = {}
  if (not my_unit) then
    -- if no unit selected, and there are units on tile
    -- the only possible action is to select other units on tile

    -- nothing is possible to do
    if (state:get_landscape_only()) then return list end

    _.each(tile_units, function(idx, unit)
      local action
      if (unit.player == current_player) then
        action = {
          policy = "click",
          hint = engine:translate('ui.radial-menu.hex.select_unit', {name = unit.name}),
          state = "available",
          images = {
            available = theme.actions.select_unit.available,
            hilight   = theme.actions.select_unit.hilight,
          },
          callback = function()
            unit:update_actions_map()
            state:set_selected_unit(unit)
          end
        }
      else
        action = {
          policy = "click",
          hint = engine:translate('ui.radial-menu.hex.unit_info', {name = unit.name}),
          state = "available",
          images = {
            available = theme.actions.information.available,
            hilight   = theme.actions.information.hilight,
          },
          callback = function()
            print("info about unit")
          end
        }
      end
      table.insert(list, action)
    end)

    return list
  end
end

function RadialMenu:_generic_actions()
  local engine = self.engine
  local state = engine.state
  local theme = engine.gear:get("theme")

  local list = {}

  -- end button
  local end_button = {
    policy = "click",
    hint = engine:translate('ui.radial-menu.general.end_turn'),
    state = "available",
    images = {
      available = theme.actions.end_turn.available,
      hilight   = theme.actions.end_turn.hilight,
    },
    callback = function()
      engine:end_turn()
    end
  }
  table.insert(list, end_button)

  -- layer switch button
  local layer_switch_button = {
    po1licy = "toggle",
    hint = engine:translate('ui.radial-menu.general.toggle_layer'),
    state = (state:get_active_layer() == 'air') and 'air' or "surface",
    states = {"surface", "air"},
    images = {
      surface = theme.actions.switch_layer.land,
      air     = theme.actions.switch_layer.air,
    },
    callback = function()
      local new_value = (state:get_active_layer() == 'air') and 'surface' or 'air'
      state:set_active_layer(new_value)
      -- print("active layer " .. new_value)
    end
  }
  table.insert(list, layer_switch_button)

  -- toggle history button
  local toggle_history_button = {
    policy = "toggle",
    hint = engine:translate('ui.radial-menu.general.toggle_history'),
    state = state:get_recent_history() and 'on' or 'off',
    states = {"on", "off"},
    images = {
      on  = theme.actions.toggle_history.on,
      off = theme.actions.toggle_history.off,
    },
    callback = function()
      local new_value = not state:get_recent_history()
      local actual_records = engine.history:get_actual_records()
      state:set_actual_records(actual_records)
      state:set_recent_history(new_value)
    end
  }
  table.insert(list, toggle_history_button)

  -- toggle landscape button
  local toggle_landscape_button = {
    policy = "toggle",
    hint = engine:translate('ui.radial-menu.general.toggle_landscape'),
    state = state:get_landscape_only() and "on" or "off",
    states = {"on", "off"},
    images = {
      on  = theme.actions.toggle_landscape.on,
      off = theme.actions.toggle_landscape.off,
    },
    callback = function()
      local new_value = not state:get_landscape_only()
      state:set_selected_unit(nil)
      state:set_landscape_only(new_value)
    end
  }
  table.insert(list, toggle_landscape_button)

  return list
end


function RadialMenu:_construct_gui()
  local engine = self.engine
  local tile = self.tile
  local theme = engine.gear:get("theme")

  local background = theme.radial_menu.background
  local w, h = background.w, background.h

  local center_x, center_y = w/2, h/2

  local up = theme.radial_menu.inner_buttons.up
  local down = theme.radial_menu.inner_buttons.down

  -- inner & outer radiuses
  local bg_r = up.available.w / 2
  local bg_R = math.max(w, h) / 2

  local is_over_bg = function(x, y)
    -- print(string.format("x = %f, y = %f, cx = %f, cy = %f", x, y, center_x, center_y))
    return math.sqrt((x - center_x)^2 + (y - center_y)^2) < bg_R
  end

  local up_lower = math.modf(h/2 - bg_r + up.available.h)
  local down_higher = math.modf(h/2 + bg_r - up.available.h)

  local is_over_up = function(x, y)
    return (math.sqrt((x - center_x)^2 + (y - center_y)^2) < bg_r) and (y < up_lower)
  end
  local is_over_down = function(x, y)
    return (math.sqrt((x - center_x)^2 + (y - center_y)^2) < bg_r) and (y > down_higher)
  end

  local gui = {
    background = {
      box     = { x = 0, y = 0, w = w, h = h},
      image   = background,
      is_over = is_over_bg,
    },
    inner = {
      up     = {
        state = "available",
        hint  = engine:translate('ui.radial-menu.hex_button'),
        image = {
          available = up.available,
          hilight   = up.hilight,
          active    = up.active,
        },
        box   = {
          x = math.modf(w/2 - up.available.w/2),
           -- w/2 because we assume, that inner button width is equal to inner radius
          y = math.modf(h/2 - up.available.w/2),
          w = up.available.w,
          h = up.available.h,
        },
        is_over = is_over_up,
      },
      down   = {
        state = "available",
        hint  = engine:translate('ui.radial-menu.general_button'),
        image = down,
        image = {
          available = down.available,
          hilight   = down.hilight,
          active    = down.active,
        },
        box = {
          x = math.modf(w/2 - down.available.w/2),
           -- w/2 because we assume, that inner button width is equal to inner radius
          y = math.modf(h/2 + down.available.w/2 - down.available.h),
          w = down.available.w,
          h = down.available.h,
        },
        is_over = is_over_down,
      },
    },
    sectors = theme.radial_menu.sectors,
    w = w,
    h = h,
  }

  local hex_actions = self:_hex_actions()
  local generic_actions = self:_generic_actions()
  local delta_angle = 2 * math.pi / #theme.radial_menu.sectors
  local image_r = bg_r + (bg_R - bg_r)/2 + 3
  local image_sample = theme.actions.end_turn.available

  gui.inner.active = (#hex_actions > 0) and gui.inner.up or gui.inner.down
  gui.inner.active.state = 'active'

  -- creates box & is_over callback
  local prepare_action = function(idx, action)
    local angle = math.pi/2 - idx * delta_angle + delta_angle / 2
    -- print("angle = " .. math.deg(angle) .. ", delta =  " .. math.deg(delta_angle))
    local c_x = image_r * math.cos(angle)
    local c_y = image_r * math.sin(angle)
    local c_l = math.sqrt(c_x^2 + c_y^2)
    local box = {
      x = math.modf(center_x + c_x - image_sample.w/2),
      y = math.modf(center_y - c_y - image_sample.h/2),
      w = image_sample.w,
      h = image_sample.h,
    }
    -- print(inspect(action))
    action.box = box

    -- is over function. (x, y) are in radial menu coordinates
    action.is_over = function(x, y)
      local dx, dy = x - center_x, y - center_y

      -- reflect on y-axis
      dy = dy * -1

      local distance = math.sqrt(dx^2 + dy^2)
      if (distance <= 0 ) then return end
      -- distance between two vectors
      local d_angle = math.acos((dx * c_x + dy * c_y ) / (distance * c_l) )
      local result = (distance < bg_R) and (distance > bg_r)
        and (d_angle < delta_angle / 2)
      -- print(string.format("dx = %f , dy = %f, cdx = %f, cdy = %f", dx, dy, c_x, c_y))
      -- print(string.format("%s : %f, %f", result, d_angle, delta_angle))
      return result
    end

    -- returns current texture
    action.get_texture = function()
      return action.images[action.state].texture
    end

    return action
  end

  gui.inner.down.actions = _.map(generic_actions, prepare_action)
  gui.inner.up.actions = _.map(hex_actions, prepare_action)

  return gui
end

function RadialMenu:_on_ui_update(show)
  local ctx      = self.drawing.context
  local gui      = self.drawing.gui
  local engine   = self.engine
  local terrain  = engine.gear:get("terrain")
  local renderer = engine.gear:get("renderer")
  local tile_context = self.tile_context

  if (show) then

    local tile_x = tile_context.x
    local tile_y = tile_context.y
    local hex_h = terrain.hex_height
    local hex_w = terrain.hex_width

    -- adjustments to radial-menu coordinates
    local delta_x, delta_y = -(tile_x + hex_w/2) + gui.w/2, -(tile_y + hex_h/2) + gui.h/2
    local adjust_box = function(box)
      return {
        x = math.modf(box.x - delta_x),
        y = math.modf(box.y - delta_y),
        w = box.w,
        h = box.h,
      }
    end

    local up = gui.inner.up
    local down = gui.inner.down

    local bg_box = adjust_box(gui.background.box)
    local up_box = adjust_box(up.box)
    local down_box = adjust_box(down.box)

    _.each(gui.inner.up.actions, function(idx, action)
      action.box = adjust_box(action.box)
    end)
    _.each(gui.inner.down.actions, function(idx, action)
      action.box = adjust_box(action.box)
    end)


    local sdl_renderer = assert(renderer.sdl_renderer)
    self.drawing.fn = function()
      -- background
      assert(sdl_renderer:copy(gui.background.image.texture, nil, bg_box))

      -- inner up & down button
      assert(sdl_renderer:copy(up.image[up.state].texture, nil, up_box))
      assert(sdl_renderer:copy(down.image[down.state].texture, nil, down_box))

      -- sector background for buttons
      for idx = 1, #gui.inner.active.actions do
        assert(sdl_renderer:copy(gui.sectors[idx].texture, nil, bg_box))
      end

      -- active state buttons
      for _, action in pairs(gui.inner.active.actions) do
        local texture = action.get_texture()
        assert(sdl_renderer:copy(texture, nil, action.box))
      end
    end

    if (not handlers_bound) then
      self.handlers_bound = true

      local mouse_move = function(event)
        -- x, y in radial-menu coordinates
        local my_x, my_y = event.x + delta_x, event.y + delta_y

        for _, action in pairs(gui.inner.active.actions) do
          if (action.policy == 'click') then
            action.state = 'available'
          end
        end

        if (gui.background.is_over(my_x, my_y)) then
          local hint = ''

          for _, region in pairs( {up, down} ) do
            local is_over = region.is_over(my_x, my_y)
            if (region.state ~= 'active') then
              local new_state = is_over and 'hilight' or 'available'
              region.state = new_state
            end
            if (is_over) then
              hint = region.hint
            else
              for _, action in pairs(gui.inner.active.actions) do
                if (action.is_over(my_x, my_y)) then
                  hint = action.hint
                  if (action.policy == 'click') then
                    action.state = 'hilight'
                  end
                end
              end
            end
          end
          engine.state:set_mouse_hint(hint)
        end
         -- stop further event propagation
        return true
      end

      local mouse_click = function(event)
        -- x, y in radial-menu coordinates
        local my_x, my_y = event.x + delta_x, event.y + delta_y
        if (gui.background.is_over(event.x + delta_x, event.y + delta_y)) then
          for _, region in pairs( {up, down} ) do
            if (region.is_over(my_x, my_y)) then
              if (gui.inner.active) then gui.inner.active.state = 'available' end
              gui.inner.active = region
              region.state = 'active'
            end
          end
          for _, action in pairs(gui.inner.active.actions) do
            if (action.is_over(my_x, my_y)) then
              -- special handle of toggle policy
              if (action.policy == 'toggle') then
                local state_index
                for idx, state in pairs(action.states) do
                  if (state == action.state) then
                    state_index = idx
                  end
                end
                assert(state_index, "cannot find state index for " .. action.state)
                if (state_index == #action.states) then
                  state_index = 1
                else
                  state_index = state_index + 1
                end
                action.state = action.states[state_index]
              end
              action.callback()
              engine.interface:remove_window(self)
            end
          end
          -- stop further event propagation
          return true
        else
          -- remove radial menu
          engine.interface:remove_window(self)
          -- allow further event propagation
          return false
        end
      end

      self.drawing.mouse_move = mouse_move
      self.drawing.mouse_click = mouse_click
      ctx.events_source.add_handler('mouse_move', self.drawing.mouse_move)
      ctx.events_source.add_handler('mouse_click', self.drawing.mouse_click)

    end

  else -- unbind everything
    self.handlers_bound = false
    ctx.events_source.remove_handler('mouse_move', self.drawing.mouse_move)
    ctx.events_source.remove_handler('mouse_click', self.drawing.mouse_click)
    self.drawing.mouse_move = nil
    self.drawing.mouse_click = nil
  end

end

function RadialMenu:bind_ctx(context)
  local engine = self.engine
  local gui = self:_construct_gui()

  local ui_update_listener = function() return self:_on_ui_update(true) end

  self.drawing.context = context
  self.drawing.ui_update_listener = ui_update_listener
  self.drawing.gui = gui

  engine.reactor:subscribe('ui.update', ui_update_listener)

  self.drawing.fn = function() end

  return {gui.w, gui.h}
end

function RadialMenu:unbind_ctx(context)
  self:_on_ui_update(false)
  self.engine.reactor:unsubscribe('ui.update', self.drawing.ui_update_listener)
  self.drawing.ui_update_listener = nil
  self.drawing.context = nil
end

function RadialMenu:set_position(x, y)
  -- ignore values
end


function RadialMenu:draw()
  self.drawing.fn()
end

return RadialMenu
