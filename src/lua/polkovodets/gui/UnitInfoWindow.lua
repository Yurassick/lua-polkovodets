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

local Widget = require ('polkovodets.gui.Widget')
local Image = require 'polkovodets.utils.Image'
local Region = require 'polkovodets.utils.Region'

local UnitInfoWindow = {}
UnitInfoWindow.__index = UnitInfoWindow
setmetatable(UnitInfoWindow, Widget)

local TTILE_FONT_SIZE = 16
local DEFAULT_FONT_SIZE = 12
local DEFAULT_COLOR = 0xAAAAAA
local HILIGHT_COLOR = 0xFFFFFF

function UnitInfoWindow.create(engine, data)
  local o = Widget.create(engine)
  setmetatable(o, UnitInfoWindow)
  o.drawing.content_fn = nil
  o.content = { active_tab = 1 }
  o.unit = assert(data)
  o.drawing.position = {0, 0}
  return o
end

function UnitInfoWindow:_render_string(label, color)
  local engine = self.engine
  local theme = engine.gear:get("theme")
  local renderer = engine.gear:get("renderer")
  local font = theme:get_font('default', DEFAULT_FONT_SIZE)
  local image = Image.create(
    renderer.sdl_renderer,
    font:renderUtf8(label, "solid", color)
  )
  return image
end

function UnitInfoWindow:_construct_info_tab()
  local engine = self.engine
  local unit = self.unit
  local theme = engine.gear:get("theme")
  local renderer = engine.gear:get("renderer")
  local font = theme:get_font('default', DEFAULT_FONT_SIZE)
  local all = {}
  local tab_data = {
    all       = all,
    active    = all,
    r_aligned = {},
    icon      = {
      hint    = engine:translate('ui.unit-info.tab.info.hint'),
      current = 'available',
      states  = theme.tabs.info,
    },
    mouse_click = function(event) end,
    mouse_move = function(event) end,
  }

  local dx, dy = 0, 0

  -- definition name
  local definition_name = Image.create(
    renderer.sdl_renderer,
    font:renderUtf8(unit.definition.name, "solid", DEFAULT_COLOR)
  )
  table.insert(tab_data.all, {
    dx = dx,
    dy = dy,
    image = definition_name,
  })

  local max_label_x = 0
  local add_row = function(key, value)
    local label = Image.create(
      renderer.sdl_renderer,
      font:renderUtf8(engine:translate(key), "solid", DEFAULT_COLOR)
    )
    table.insert(tab_data.all, {
      dx = dx,
      dy = tab_data.all[#tab_data.all].dy + tab_data.all[#tab_data.all].image.h + 5,
      image = label,
    })
    local value_img = self:_render_string(value, DEFAULT_COLOR);
    local value_descr = {
      dx = tab_data.all[#tab_data.all].dx + tab_data.all[#tab_data.all].image.w + 15,
      dy = tab_data.all[#tab_data.all].dy,
      image = value_img,
    }
    max_label_x = math.max(max_label_x, value_descr.dx)
    table.insert(all, value_descr)
    table.insert(tab_data.r_aligned, value_descr)
  end

  -- unit definition info
  add_row('ui.unit-info.size', engine:translate('db.unit.size.' .. unit.definition.size))
  add_row('ui.unit-info.class', engine:translate('db.unit-class.' .. unit.definition.unit_class.id))
  add_row('ui.unit-info.spotting', tostring(unit.definition.spotting))
  -- unit info
  add_row('ui.unit-info.experience', tostring(unit.data.experience))
  if (unit.definition.unit_class['type'] == 'ut_land') then
    add_row('ui.unit-info.entrenchement', tostring(unit.data.entr))
  end
  add_row('ui.unit-info.state', engine:translate('db.unit.state.' .. unit.data.state))
  add_row('ui.unit-info.orientation', engine:translate('db.unit.orientation.' .. unit.data.orientation))

  -- re-allign r-aligned labels (values) to the same right-most border
  _.each(tab_data.r_aligned, function(idx, e)
    e.dx = max_label_x
  end)

  return tab_data
end

function UnitInfoWindow:_construct_problems_tab()
  local engine = self.engine
  local unit = self.unit
  local theme = engine.gear:get("theme")
  local renderer = engine.gear:get("renderer")
  local font = theme:get_font('default', DEFAULT_FONT_SIZE)
  local all = {}
  local tab_data = {
    all       = all,
    active    = all,
    r_aligned = {},
    icon      = {
      hint    = engine:translate('ui.unit-info.tab.problems.hint'),
      current = 'available',
      states  = theme.tabs.problems,
    },
    mouse_click = function(event) end,
    mouse_move = function(event) end,
  }

  local dx, dy = 0, 0

  local problems = unit:report_problems()

  local header = (#problems > 0) and 'ui.unit-info.tab.problems.present' or 'ui.unit-info.tab.problems.absent'
  table.insert(tab_data.all, {
    dx = dx,
    dy = dy,
    image = Image.create(
      renderer.sdl_renderer,
      font:renderUtf8(engine:translate(header), "solid", DEFAULT_COLOR)
    )
  })

  local add_row = function(text)
    local label = Image.create(
      renderer.sdl_renderer,
      font:renderUtf8(text, "solid", DEFAULT_COLOR)
    )
    print(inspect(tab_data.all))
    table.insert(tab_data.all, {
      dx = dx,
      dy = tab_data.all[#tab_data.all].dy + tab_data.all[#tab_data.all].image.h + 5,
      image = label,
    })
  end

  for _, problem_info in pairs(problems) do
    add_row(problem_info.message)
  end

  return tab_data
end

function UnitInfoWindow:_construct_units_tab(tab_hint, tab_icon_states, iterator)
  local engine = self.engine
  local theme = engine.gear:get("theme")
  local font = theme:get_font('default', DEFAULT_FONT_SIZE)
  local tab_data = {
    all       = {},
    active    = {},
    r_aligned = {},
    icon      = {
      hint    = engine:translate(tab_hint),
      current = 'available',
      states  = tab_icon_states,
    },
    mouse_click = function() end,
    mouse_move = "to be defined later",
  }
  local dx, dy = 0, 0
  local lines = {}
  local hilighted_line
  -- actualize lines, i.e show possibly only one hilighted item
  local fill_active = function(x, y)
    hilighted_line = nil
    tab_data.active = {}
    tab_data.all    = {}
    for idx, line in pairs(lines) do
      local is_over = line.region:is_over(x, y)
      if (is_over) then hilighted_line = idx end
      local active = is_over and line.hilight or line.default
      table.insert(tab_data.active, active)
      table.insert(tab_data.active, line.flag)
      table.insert(tab_data.all   , line.default)
      table.insert(tab_data.all   , line.hilight)
      table.insert(tab_data.all,    line.flag)
    end
  end

  -- create all lines, i.e. unit label (default/hilight) + icon
  for idx, unit in iterator() do
    local name = self:_render_string(unit.name, DEFAULT_COLOR)
    local name_hilight = self:_render_string(unit.name, HILIGHT_COLOR)
    local unit_flag = unit.definition.nation.unit_flag
    local unit_flag_descr = {
      dx = dx + name.w + 5,
      dy = dy + math.modf(name.h/2 - unit_flag.h/2),
      image = unit_flag,
    }
    local line_descr = {
      default = { dx = dx, dy = dy, image = name },
      hilight = { dx = dx, dy = dy, image = name_hilight },
      region  = Region.create(dx, dy, unit_flag_descr.dx + unit_flag_descr.image.w, dy + name.h),
      flag    = unit_flag_descr,
      unit    = unit,
    }
    table.insert(lines, line_descr)
    dy = dy + name.h + 5
  end

  -- fill with defaults
  fill_active(-1, -1)
  tab_data.mouse_move = fill_active
  tab_data.mouse_click = function(x, y)
    if (hilighted_line) then
      local unit = lines[hilighted_line].unit
      engine.interface:add_window('unit_info_window', unit)
    end
  end
  return tab_data
end

function UnitInfoWindow:_construct_attachments_tab()
  local engine = self.engine
  local theme = engine.gear:get("theme")
  local unit = self.unit
  if (#unit.data.attached > 0) then
    local iterator_factory = function()
      local idx = 1
      local iterator = function()
        if (idx <= #unit.data.attached) then
          local prev_idx = idx
          idx = idx + 1
          return prev_idx, unit.data.attached[prev_idx]
        end
      end
      return iterator, nil, true
    end
    return self:_construct_units_tab('ui.unit-info.tab.attachments.hint', theme.tabs.attachments, iterator_factory)
  end
end

function UnitInfoWindow:_construct_management_tab()
  local engine = self.engine
  local theme = engine.gear:get("theme")
  local unit = self.unit
  local k, manage_level = unit:is_capable('MANAGE_LEVEL')
  if (not manage_level) then

    local iterator_factory = function()
      -- create list of manager units, the top-level managers come last
      local manager_units = {}
      local manager_unit = unit
      while (manager_unit.data.managed_by and (manager_unit.id ~= manager_unit.data.managed_by)) do
        manager_unit = engine:get_unit(manager_unit.data.managed_by)
        table.insert(manager_units, manager_unit)
      end
      -- table.remove(manager_units, #manager_unit)
      local idx = 1
      local iterator = function()
        if (idx <= #manager_units) then
          local prev_idx = idx
          idx = idx + 1
          return prev_idx, manager_units[prev_idx]
        end
      end
      return iterator, nil, true
    end
    local hint = 'ui.unit-info.tab.management.hint'
    local icon_states = theme.tabs.attachments
    return self:_construct_units_tab(hint, icon_states, iterator_factory)
  end
end

function UnitInfoWindow:_construct_weapon_tabs()
  local engine = self.engine
  local theme = engine.gear:get("theme")
  local font = theme:get_font('default', DEFAULT_FONT_SIZE)
  local class_presents = {} -- k: class_id, value: boolean
  local unit = self.unit

   -- k: class_id, v: array of weapon instances
  local wi_for_class = {}
  -- step 1: fetch classes from types from unit definitions
  local types_for = engine.gear:get("weapons/types::map")
  _.each(unit:all_units(), function(idx, u)
    _.each(u.definition.staff, function(weapon_type_id, _)
      local class_id = types_for[weapon_type_id].class.id
      wi_for_class[class_id] = {}
      class_presents[class_id] = true
    end)
  end)

  -- step 2: fetch available classes & related weapon instances
  _.each(unit.staff, function(idx, wi)
    local class = wi:get_class()
    class_presents[class.id] = true
    local wi_list = wi_for_class[class.id] or {}
    table.insert(wi_list, wi)
    wi_for_class[class.id] = wi_list
  end)

  -- get classes in the correct order
  local classes = _.select(engine.gear:get("weapons/classes"), function(idx, class)
    return class_presents[class.id]
  end)

  local tabs = _.map(classes, function(idx, class)
    local icon_states = {}
    _.each({'active', 'available', 'hilight'}, function(idx, style)
      icon_states[style] = class:get_icon(style)
    end)
    local all = {}
    local tab_data = {
      all       = all,
      active    = all,
      r_aligned = {},
      icon      = {
        hint    = engine:translate('db.weapon-class.' .. class.id),
        current = 'available',
        states  = icon_states,
      },
      mouse_click = function(event) end,
      mouse_move = function(event) end,
    }
    -- render per weapon instance: weapon name and available quantity
    local dx, dy = 0, 0
    local weapon_instances = wi_for_class[class.id]
    for idx, wi in ipairs(weapon_instances) do
      local name = self:_render_string(wi.weapon.name, DEFAULT_COLOR)
      table.insert(tab_data.all, {
        dx = dx,
        dy = dy,
        image = name,
      })
      local quantity = self:_render_string(tostring(wi.data.quantity), DEFAULT_COLOR)
      local quantity_desc = {
        dx = dx + name.w + 5,
        dy = dy,
        image = quantity,
      }
      table.insert(tab_data.all, quantity_desc)
      table.insert(tab_data.r_aligned, quantity_desc)
      dy = dy + name.h + 5
    end
    return tab_data
  end)


  return tabs
end


function UnitInfoWindow:_construct_gui()
  local engine = self.engine
  local renderer = engine.gear:get("renderer")
  local theme = engine.gear:get("theme")
  local unit = self.unit

  local elements = {}

  --[[ header start ]]--
  -- flag
  local flag = unit.definition.nation.flag
  table.insert(elements, {
    dx    = 5,
    dy    = 0,
    image = flag,
  })

  -- title (unit name)
  local title_font = theme:get_font('default', TTILE_FONT_SIZE)
  local title = Image.create(
    renderer.sdl_renderer,
    title_font:renderUtf8(unit.name, "solid", DEFAULT_COLOR)
  )
  table.insert(elements, {
    dx    = elements[#elements].dx + elements[#elements].image.w + 5,
    dy    = 0,
    image = title,
  })

  local max_w = elements[#elements].dx + elements[#elements].image.w + 5
  local max_h = math.max(title.h, flag.h)
  -- reposition title/flag to be on the same Y-center
  _.each(elements, function(idx, e)
    e.dy = math.modf((max_h - e.image.h) / 2)
  end)

  local dy = max_h + 10
  local dx = 10
  --[[ header end ]]--

  local padding = dx -- l and r padding
  local tabs = {}
  local max_tab_w, max_tab_h = 0, 0
  local add_tab = function(tab)
    if (tab) then
      table.insert(tabs, tab)
      local w = _.max(tab.all, function(e)
        return e.dx + e.image.w
      end)
      local h = _.max(tab.all, function(e)
        return e.dy + e.image.h
      end)
      max_tab_w = math.max(max_tab_w, (w or 0) + padding * 2)
      max_tab_h = math.max(max_tab_h, h or 0)
    end
  end

  add_tab(self:_construct_info_tab())
  add_tab(self:_construct_problems_tab())
  add_tab(self:_construct_attachments_tab())
  add_tab(self:_construct_management_tab())
  _.each(self:_construct_weapon_tabs(), function(idx, tab)
    add_tab(tab)
  end)

  -- post-process tabs: adjust tab icons, dx, dy for all elements,
  local tab_icon_dx, tab_icon_dy = dx, dy
  local tab_line = 4 + tabs[1].icon.states[tabs[1].icon.current].h
  dy = dy + tab_line
  _.each(tabs, function(idx, tab)
    tab.icon.dx = tab_icon_dx
    tab.icon.dy = tab_icon_dy
    tab_icon_dx = tab_icon_dx + tab.icon.states[tab.icon.current].w + 2
    _.each(tab.all, function(idx, e)
      e.dx = e.dx + dx
      e.dy = e.dy + dy
    end)
  end)

  -- it might be that tabs icon line is the most wide
  max_w = math.max(max_tab_w, max_w, tab_icon_dx + 10)

  -- post-process tabs: adjust r-aligned items
  _.each(tabs, function(idx, tab)
    _.each(tab.r_aligned, function(idx, e)
      e.dx = max_w - e.image.w - 10
    end)
  end)

  local tabs_region = {
    x_min = dx,
    y_min = dy,
    x_max = max_w,
    y_max = dy + max_tab_h,
  }

  local active_tab = self.content.active_tab
  tabs[active_tab].icon.current = 'active'
  local gui = {
    tabs         = tabs,
    tabs_region  = tabs_region,
    active_tab   = active_tab,
    elements     = elements,
    content_size = {
      w = max_w,
      h = dy + max_tab_h,
    },
  }
  return gui
end

function UnitInfoWindow:_on_ui_update(show)
  local engine = self.engine
  local context = self.drawing.context

  local handlers_bound = self.handlers_bound

  if (show) then
    local renderer = engine.gear:get("renderer")
    local theme = engine.gear:get("theme")

    engine.state:set_mouse_hint('')
    local gui = self.drawing.gui

    local content_w = gui.content_size.w
    local content_h = gui.content_size.h
    local x, y = table.unpack(self.drawing.position)

    local content_x, content_y = x + self.contentless_size.dx, y + self.contentless_size.dy

    local window_region = Region.create(x, y, x + self.contentless_size.w + content_w, y + self.contentless_size.h + content_h)
    local tab_x_min, tab_y_min = content_x + gui.tabs_region.x_min, content_y + gui.tabs_region.y_min
    local tab_x_max, tab_y_max = content_x + gui.tabs_region.x_max, content_y + gui.tabs_region.y_max
    local tab_content_region = Region.create(tab_x_min, tab_y_min, tab_x_max, tab_y_max)

    local tab_icon_regions = _.map(gui.tabs, function(idx, tab)
      local icon_data = tab.icon
      local tab_image = icon_data.states[icon_data.current]
      local x, y = content_x + icon_data.dx, content_y + icon_data.dy
      return Region.create(x, y, x + tab_image.w, y + tab_image.h)
    end)

    local is_over_tab_icons_region = function(x,y)
      for idx, tab_icon_area in ipairs(tab_icon_regions) do
        if (tab_icon_area:is_over(x, y)) then
          return idx
        end
      end
    end
    Widget.update_drawer(self, x, y, content_w, content_h)


    local sdl_renderer = assert(renderer.sdl_renderer)
    self.drawing.content_fn = function()
      -- background
      assert(sdl_renderer:copy(theme.window.background.texture, nil,
        {x = content_x, y = content_y, w = content_w, h = content_h}
      ))

      local element_drawer = function(idx, e)
        local image = e.image
        assert(sdl_renderer:copy(image.texture, nil,
          {x = content_x + e.dx, y = content_y + e.dy, w = image.w, h = image.h}
        ))
      end
      -- header
      _.each(gui.elements, element_drawer)

      -- draw active tab active elements
      local tab_elements = gui.tabs[gui.active_tab].active
      _.each(tab_elements, element_drawer)

      -- draw all tab labels
      _.each(gui.tabs, function(idx, tab)
        local icon_data = tab.icon
        local tab_image = icon_data.states[icon_data.current]
        assert(sdl_renderer:copy(tab_image.texture, nil,
          {x = content_x + icon_data.dx, y = content_y + icon_data.dy, w = tab_image.w, h = tab_image.h}
        ))
      end)
      Widget.draw(self)
    end

    if (not handlers_bound) then
      self.handlers_bound = true
      local mouse_click = function(event)
        if (window_region:is_over(event.x, event.y)) then
          local idx = is_over_tab_icons_region(event.x, event.y)
          if (idx) then -- swithing tab
            local prev_tab = gui.tabs[gui.active_tab]
            local new_tab = gui.tabs[idx]
            prev_tab.icon.current = 'available'
            new_tab.icon.current = 'active'
            gui.active_tab = idx
            -- remember active tab between ctx bind/unbind
            self.content.active_tab = idx
          else -- some action inside tab content, delegate
            gui.tabs[gui.active_tab]:mouse_click(event)
          end
        else
          -- just close the window
          engine.interface:remove_window(self)
        end
        return true -- stop further event propagation
      end

      local mouse_move = function(event)
        -- engine.state:set_mouse_hint('')
        -- remove hilight from all tab icons, except the active one
        for idx, tab in ipairs(gui.tabs) do
          local icon = tab.icon
          if (idx ~= gui.active_tab) then
            icon.current = 'available'
          end
        end
        local idx = is_over_tab_icons_region(event.x, event.y)
        if (idx) then
          engine.state:set_mouse_hint(gui.tabs[idx].icon.hint)
          if (idx ~= gui.active_tab) then
            gui.tabs[idx].icon.current = 'hilight'
          end
        end
        if (not(idx) and tab_content_region:is_over(event.x, event.y)) then
          -- need to shift coordinate system
          gui.tabs[gui.active_tab].mouse_move(event.x - tab_x_min, event.y - tab_y_min)
        end
        return true -- stop further event propagation
      end


      context.events_source.add_handler('mouse_click', mouse_click)
      context.events_source.add_handler('mouse_move', mouse_move)
      self.content.mouse_click = mouse_click
      self.content.mouse_move = mouse_move
    end
  elseif (self.handlers_bound) then  -- unbind everything
    self.handlers_bound = false
    context.events_source.remove_handler('mouse_click', self.content.mouse_click)
    context.events_source.remove_handler('mouse_move', self.content.mouse_move)
    self.content.mouse_click = nil
    self.content.mouse_move = nil
    self.drawing.content_fn = function() end
  end
end

function UnitInfoWindow:bind_ctx(context)
  local engine = self.engine
  local gui = self:_construct_gui()

  local ui_update_listener = function() return self:_on_ui_update(true) end

  self.drawing.context = context
  self.drawing.ui_update_listener = ui_update_listener
  self.drawing.gui = gui

  engine.reactor:subscribe('ui.update', ui_update_listener)

  local w, h = gui.content_size.w + self.contentless_size.w, gui.content_size.h + self.contentless_size.h
  return {w, h}
end

function UnitInfoWindow:set_position(x, y)
  self.drawing.position = {x, y}
end

function UnitInfoWindow:unbind_ctx(context)
  self:_on_ui_update(false)
  self.engine.reactor:unsubscribe('ui.update', self.drawing.ui_update_listener)
  self.drawing.ui_update_listener = nil
  self.drawing.context = nil
end

function UnitInfoWindow:draw()
  self.drawing.content_fn()
end

return UnitInfoWindow
