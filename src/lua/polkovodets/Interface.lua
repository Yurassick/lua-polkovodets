--[[

Copyright (C) 2015 Ivan Baidakou

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

-- preload
local GamePanel = require ('polkovodets.gui.GamePanel')
local UnitPanel = require ('polkovodets.gui.UnitPanel')
require ('polkovodets.gui.BattleDetailsWindow')
require ('polkovodets.gui.BattleSelectorPopup')
local WeaponCasualitiesDetailsWindow = require ('polkovodets.gui.WeaponCasualitiesDetailsWindow')

local Interface = {}
Interface.__index = Interface

function Interface.create(engine)
  local o = {
    engine = engine,
    context = nil,
    drawing = {
      fn          = nil,
      mouse_click = nil,
      objects     = {},
      obj_by_type = {
        game_panel = nil,
      }
    }
  }
  setmetatable(o, Interface)

  local game_panel = GamePanel.create(engine)
  table.insert(o.drawing.objects, game_panel)
  o.drawing.obj_by_type.game_panel = game_panel

  local unit_panel = UnitPanel.create(engine)
  table.insert(o.drawing.objects, unit_panel)
  o.drawing.obj_by_type.unit_panel = unit_panel

  engine.interface = o

  return o
end

function Interface:bind_ctx(context)
  local font = context.theme.fonts.active_hex
  local outline_color = context.theme.data.active_hex.outline_color
  local color = context.theme.data.active_hex.color

  local w, h = context.renderer.window:getSize()
  local sdl_renderer = context.renderer.sdl_renderer

  local render_label = function(surface)
    local texture = assert(sdl_renderer:createTextureFromSurface(surface))
    local sw, sh = surface:getSize()
    local label_x = math.modf(w/2 - sw/2)
    local label_y = 25 - math.modf(sh/2)
    return {
      texture = texture,
      dst     = {x = label_x, y = label_y, w = sw, h = sh},
    }
  end

  local interface_ctx = _.clone(context, true)
  interface_ctx.window = {w = w, h = h}

  local rendered_hint
  local labels = {}
  local update_hint = function()
    local hint = context.state.mouse_hint
    if (hint ~= rendered_hint) then
      labels = {}
      if (hint and #hint > 0) then
        font:setOutline(context.theme.data.active_hex.outline_width)
        table.insert(labels, render_label(font:renderUtf8(hint, "solid", outline_color)))
        font:setOutline(0)
        table.insert(labels, render_label(font:renderUtf8(hint, "solid", color)))
      end
    end
  end
  update_hint()

  local draw_fn = function()
    update_hint()
    for idx, label_data in pairs(labels) do
      assert(sdl_renderer:copy(label_data.texture, nil , label_data.dst))
    end
    _.each(self.drawing.objects, function(k, v) v:draw() end)
  end

  _.each(self.drawing.objects, function(k, v) v:bind_ctx(interface_ctx) end)
  self.drawing.fn = draw_fn
  self.context = interface_ctx
end

function Interface:unbind_ctx(context)
  _.each(self.drawing.objects, function(k, v) v:unbind_ctx(context) end)
  self.drawing.fn = nil
end

function Interface:draw()
  self.drawing.fn()
end

function Interface:add_window(id, data)
  -- constuct short class name, by removing _ and capitalizing
  -- 1st letters
  local class_name = ''
  local start_search = 1
  local do_search = true
  while (do_search) do
    local s, e = string.find(id, '_', start_search, true)
    if (s) then
      local capital = string.upper(string.sub(id, start_search, start_search))
      local tail = string.sub(id, start_search + 1, s - 1)
      class_name = class_name .. capital .. tail
      start_search = e + 1
    else
      do_search = false
      local capital = string.upper(string.sub(id, start_search, start_search))
      local tail = string.sub(id, start_search + 1)
      class_name = class_name .. capital .. tail
    end
  end
  -- print("class for " .. id .. " " .. class_name)
  local class = require ('polkovodets.gui.' .. class_name)
  local window = class.create(self.engine, data)

  table.insert(self.drawing.objects, window)

  window:bind_ctx(self.context)

  print("created window" .. class_name)
  self.engine.mediator:publish({ "view.update" })
end

function Interface:remove_window(window, do_not_emit_update)
  local idx
  for i, o in ipairs(self.drawing.objects) do
    if (o == window) then
      idx = i
      break
    end
  end
  assert(idx, "cannot find window to remove")
  window:unbind_ctx(self.context)
  table.remove(self.drawing.objects, idx)
  if (not do_not_emit_update) then
    self.engine.mediator:publish({ "view.update" })
  end
end

return Interface
