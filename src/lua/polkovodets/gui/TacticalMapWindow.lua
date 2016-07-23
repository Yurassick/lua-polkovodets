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

local _ = require ("moses")
local inspect = require('inspect')

local SDL = require "SDL"
local Image = require 'polkovodets.utils.Image'
local Region = require 'polkovodets.utils.Region'
local OrderedHandlers = require 'polkovodets.utils.OrderedHandlers'


local TacticalMapWindow = {}
TacticalMapWindow.__index = TacticalMapWindow

local SCROLL_TOLERANCE = 20
-- how many tiles are shifted on scroll
local SCROLL_DELTA = 2

function TacticalMapWindow.create(engine)
  local map = engine.gear:get("map")
  local hex_geometry = engine.gear:get("hex_geometry")
  local o = {
    engine           = engine,
    map              = map,
    hex_geometry     = hex_geometry,
    active_tile      = {1, 1},
    properties       = {
      floating = false,
    },
    drawing          = {
      fn       = nil,
      idle     = nil,
      objects  =  {},
      position = {0, 0},
      -- k: tile_id, value: ordered set of callbacks
      proxy       = {
        mouse_move  = {},
        mouse_click = {},
      }
    },
    frame = {
      -- in hex coordinates
      hex_box = {
        x = 1,
        y = 1,
        w = 0, -- be calculated later
        h = 0, -- be calculated later
      },
      texture = nil,
    },
  }
  setmetatable(o, TacticalMapWindow)
  return o
end

function TacticalMapWindow:_construct_gui()
  local engine = self.engine
  local renderer = self.engine.gear:get("renderer")
  local window_w, window_h = renderer:get_size()

  local gui = {
    content_size = {
      w = window_w,
      h = window_h,
    }
  }
  return gui
end

function TacticalMapWindow:_update_frame(hx, hy)
  local frame = self.frame
  local gui = self.drawing.gui
  local geometry = self.engine.gear:get("hex_geometry")
  local renderer = self.engine.gear:get("renderer")
  local map = self.map

  -- frame = window
  local frame_w, frame_h = gui.content_size.w, gui.content_size.h

  local w = math.ceil( frame_w / geometry.x_offset ) + 1
  local h = math.ceil( frame_h / geometry.height ) + 1

  frame.hex_box.x = hx
  frame.hex_box.y = hy
  frame.hex_box.w = w
  frame.hex_box.h = h
  print(string.format("frame x, y, h, w = %d:%d %d:%d", hx, hy, w, h))
end


function TacticalMapWindow:_get_texture()
  local engine = self.engine
  local theme = engine.gear:get("theme")
  local renderer = engine.gear:get("renderer")
  local sdl_renderer = renderer.sdl_renderer
  local gui = self.drawing.gui

  -- draw!
  local format = theme.window.background.texture:query()
  local texture = assert(sdl_renderer:createTexture(format, SDL.textureAccess.Target, gui.content_size.w, gui.content_size.h))
  assert(sdl_renderer:setTarget(texture))
  _.each(self.drawing.objects, function(k, v) v:draw() end)
  assert(sdl_renderer:setTarget(nil))

  return texture
end

function TacticalMapWindow:_prepare_context()
  local engine = self.engine
  local state = engine.state
  local theme = engine.gear:get("theme")
  local renderer = engine.gear:get("renderer")
  local gui = self.drawing.gui
  local map = self.map
  local frame = self.frame

  local hex_geometry = self.hex_geometry
  local context = self.drawing.context

  local start_map_x = self.frame.hex_box.x - 1
  local start_map_y = self.frame.hex_box.y - 1

  local map_sw = frame.hex_box.w
  local map_sh = frame.hex_box.h

  local visible_area_iterator = function(callback)
    for i = 1,map_sw do
      local tx = i + start_map_x
      for j = 1,map_sh do
        local ty = j + start_map_y
        if (tx <= map.width and ty <= map.height) then
          local tile = map.tiles[tx][ty]
          if (not tile) then error(string.format("tile [%d:%d] not found", tx, ty)) end
          callback(tile)
        end
      end
    end
  end

  local tile_visibility_test = function(tile)
    local x, y = tile.data.x, tile.data.y
    local result
      =   (x >= start_map_x and x <= map_sw)
      and (y >= start_map_y and y <= map_sh)
    return result
  end

  local active_layer = state:get_active_layer()
  local map_context = {
    tile_visibility_test = tile_visibility_test,
    screen = {
      offset = {
        -((start_map_x + 1 ) * hex_geometry.x_offset),
        -((start_map_y + 1 ) * hex_geometry.height),
      }
    },
    active_layer = active_layer,
    events_source  = self:_get_event_source(),
    subordinated = {}
  }

  local u = state:get_selected_unit()

  local active_x, active_y = table.unpack(self.active_tile)
  local active_tile = map.tiles[active_x][active_y]
  local hilight_unit = u or (active_tile and active_tile:get_unit(active_layer))

  if (hilight_unit) then
    for idx, subordinated_unit in pairs(hilight_unit:get_subordinated(true)) do
      local tile = subordinated_unit.tile
      -- tile could be nil if unit is attached to some other
      if (tile) then
        map_context.subordinated[tile.id] = true
      end
    end
  end

  local my_unit_movements = function(k, v)
    if (u and v.action == 'unit/move') then
      local unit_id = v.context.unit_id
      return (unit_id and unit_id == u.id)
    end
  end
  local battles_cache = {}
  local battles = function(k, v)
    if ((v.action == 'battle') and (not battles_cache[v.context.tile])) then
      local tile_id = v.context.tile
      battles_cache[tile_id] = true
      local tile = map:lookup_tile(tile_id)
      assert(tile)
      return true
    end
  end

  local opponent_movements = function(k, v)
    if (v.action == 'unit/move') then
      local unit_id = v.context.unit_id
      local unit = engine:get_unit(unit_id)
      local show = unit.player ~= state:get_current_player()
      return show
    end
  end

  local actual_records = state:get_actual_records()

  -- battles are always shown
  local shown_records = {}

  if (not state:get_landscape_only()) then
    shown_records = _.select(actual_records, battles)
    if (u) then
      shown_records = _.append(shown_records, _.select(actual_records, my_unit_movements))
    end

    if (state:get_recent_history()) then
      shown_records = _.append(shown_records, _.select(actual_records, opponent_movements))
    end
    -- print("shown records " .. #shown_records)
  end

  -- propagete drawing context
  local drawers = {}
  local drawers_per_tile = {} -- k: tile_id, v: list of drawers
  local add_drawer = function(tile_id, drawer)
    table.insert(drawers, drawer)
    if (tile_id) then
      local existing_tile_drawers = drawers_per_tile[tile_id] or {}
      table.insert(existing_tile_drawers, drawer)
      drawers_per_tile[tile_id] = existing_tile_drawers
    end
  end
  -- self:bind_ctx(context)
  visible_area_iterator(function(tile) add_drawer(tile.id, tile) end)
  _.each(shown_records, function(k, v)
    local tile_id = (v.action == 'battle') and v.context.tile
    add_drawer(tile_id, v)
  end)

  _.each(drawers, function(k, v) v:bind_ctx(map_context) end)

  self.drawing.map_context = map_context
  self.drawing.objects = drawers
  self.drawing.drawers_per_tile = drawers_per_tile
end


function TacticalMapWindow:_get_event_source()
  return {
    add_handler    = function(event_type, tile_id, cb) return self:_add_hanlder(event_type, tile_id, cb) end,
    remove_handler = function(event_type, tile_id, cb) return self:_remove_hanlder(event_type, tile_id, cb) end,
  }
end


function TacticalMapWindow:_add_hanlder(event_type, tile_id, cb)
  assert(event_type and tile_id and cb)
  local tile_to_set = assert(self.drawing.proxy[event_type])
  local set = tile_to_set[tile_id] or OrderedHandlers.new()
  set:insert(cb)
  tile_to_set[tile_id] = set
end


function TacticalMapWindow:_remove_hanlder(event_type, tile_id, cb)
  assert(event_type and tile_id and cb)
  local tile_to_set = assert(self.drawing.proxy[event_type])
  local set = assert(tile_to_set[tile_id])
  set:remove(cb)
end

function TacticalMapWindow:_on_map_update()
  local context = self.drawing.context
  self:unbind_ctx()
  self:bind_ctx(context)
  self:_on_ui_update()
end


function TacticalMapWindow:_on_ui_update()

  local engine = self.engine
  local state = engine.state
  local interface = engine.interface
  local map_context = self.drawing.map_context
  local context = self.drawing.context
  local map = self.map
  local frame = self.frame
  local gui = self.drawing.gui

  local handlers_bound = self.handlers_bound
  if (not handlers_bound) then
    self.handlers_bound = true
    local sdl_renderer = self.engine.gear:get("renderer").sdl_renderer

    self:_prepare_context()
    local texture = self:_get_texture()

    self.drawing.fn = function()
      assert(sdl_renderer:copy(texture, nil, nil))
    end

    local mouse_move = function(event)
      local new_tile = map:pointer_to_tile(event.x, event.y, self.hex_geometry, 0 --[[ gui.map.x ]], 0 --[[ gui.map_y ]])
      if (not new_tile) then return end
      local tile_new = map.tiles[new_tile[1]][new_tile[2]]
      event.tile_id = tile_new.id
      local tile_old = state:get_active_tile()
      if (new_tile and ((tile_old.data.x ~= new_tile[1]) or (tile_old.data.y ~= new_tile[2])) ) then
        engine.state:set_active_tile(tile_new)
        -- print("refreshing " .. tile_old.id .. " => " .. tile_new.id)

        local refresh = function(tile)
          local list = self.drawing.drawers_per_tile[tile.id]
          if (list) then
            for idx, drawer in pairs(list) do
              drawer:unbind_ctx(self.drawing.map_context)
              drawer:bind_ctx(self.drawing.map_context)
            end
          end
        end
        refresh(tile_old)
        refresh(tile_new)

        -- apply handlers for old tile
        local ordered_handlers = self.drawing.proxy.mouse_move[tile_old.id]
        if (ordered_handlers) then
          ordered_handlers:apply(function(cb) return cb(event) end)
        end
      end

      -- apply hanlders for the new/current tile
      local ordered_handlers = self.drawing.proxy.mouse_move[tile_new.id]
      if (ordered_handlers) then
        ordered_handlers:apply(function(cb) return cb(event) end)
      end
    end

    local map_region = Region.create(0, 0, gui.content_size.w, gui.content_size.h)

    local idle = function(event)
      if (interface:opened_window_count() == 1) then

        local x, y = event.x, event.y
        local hx, hy = frame.hex_box.x, frame.hex_box.y
        local refresh = false
        local map_x, map_y = frame.hex_box.x, frame.hex_box.y

        print(string.format("y_max = %d, y = %d, map_y = %d, hexbox.h = %d", map_region.y_max, y, map_y, frame.hex_box.h))

        if ((math.abs(map_region.y_min - y) < SCROLL_TOLERANCE) and map_y > SCROLL_DELTA) then
          hy = hy - SCROLL_DELTA
          refresh = true
        elseif ((math.abs(map_region.y_max - y) < SCROLL_TOLERANCE) and ( (map_y + frame.hex_box.h + SCROLL_DELTA) < map.height)) then
          hy = hy + SCROLL_DELTA
          refresh = true
        elseif ((math.abs(map_region.x_min - x) < SCROLL_TOLERANCE) and map_x > SCROLL_DELTA) then
          hx = hx - SCROLL_DELTA
          refresh = true
        elseif ((math.abs(map_region.x_max - x) < SCROLL_TOLERANCE) and ( (map_x + frame.hex_box.w + SCROLL_DELTA) < map.width)) then
          hx = hx + SCROLL_DELTA
          refresh = true
        end


        if (refresh) then
          print("frame_pos = " .. inspect(frame_pos))
          self:_update_frame(hx, hy)
          self:_on_map_update()
          engine.reactor:publish("event.delay", 50)
        end
        return true
      end
    end

    self.drawing.mouse_move = mouse_move
    self.drawing.idle = idle

    context.events_source.add_handler('idle', idle)
    context.events_source.add_handler('mouse_move', mouse_move)
  end
end


function TacticalMapWindow:bind_ctx(context)
  local engine = self.engine

  -- remember ctx first, as it is involved in gui construction
  self.drawing.context = context
  local gui = self:_construct_gui()
  local ui_update_listener = function()
    self:_update_frame(self.frame.hex_box.x, self.frame.hex_box.y)
    return self:_on_ui_update()
  end

  self.drawing.ui_update_listener = ui_update_listener
  self.drawing.gui = gui

  engine.reactor:subscribe('ui.update', ui_update_listener)

  return {gui.content_size.w, gui.content_size.h}
end


function TacticalMapWindow:unbind_ctx()

  local engine = self.engine
  local map_context = self.drawing.map_context
  local context = self.drawing.context

  _.each(self.drawing.objects, function(k, v) v:unbind_ctx(map_context) end)
  self.drawing.objects = {}

  self.engine.reactor:unsubscribe('ui.update', self.drawing.ui_update_listener)
  context.events_source.remove_handler('mouse_move', self.drawing.mouse_move)
  context.events_source.remove_handler('idle', self.drawing.idle)

  self.drawing.ui_update_listener = nil
  self.drawing.mouse_move = nil
  self.drawing.idle = nil
  self.drawing.context = nil

  self.handlers_bound = false
end


function TacticalMapWindow:set_position(x, y)
  -- completely draw over all other objects (map), i.e. ignore this settings
  -- self.drawing.position = {x, y}
end


function TacticalMapWindow:draw()
  self.drawing.fn()
end



return TacticalMapWindow

