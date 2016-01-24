--[[

Copyright (C) 2015,2016 Ivan Baidakou

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

local Unit = {}
Unit.__index = Unit

local _ = require ("moses")
local inspect = require('inspect')
local SDL = require "SDL"
local Region = require 'polkovodets.utils.Region'
local Vector = require 'polkovodets.utils.Vector'


function Unit.create(engine, data, player)
   assert(player, "unit should have player assigned")
   assert(data.id)
   assert(data.unit_definition_id)
   assert(data.x)
   assert(data.y)
   assert(data.staff)
   assert(data.state)
   assert(data.name)
   assert(data.entr)
   assert(data.exp)
   local orientation = assert(data.orientation)
   assert(string.find(orientation,'right') or string.find(orientation, 'left'))


   local unit_lib = engine.unit_lib
   local definition = assert(unit_lib.units.definitions[data.unit_definition_id])
   local x,y = tonumber(data.x), tonumber(data.y)
   local tile = assert(engine.map.tiles[x + 1][y + 1])

   local possible_efficiencies = {'high', 'avg', 'low'}

   local o = {
      id         = data.id,
      name       = data.name,
      engine     = engine,
      player     = player,
      tile       = tile,
      definition = definition,
      data = {
         entr         = data.entr,
         experience   = data.exp,
         staff        = data.staff,
         state        = data.state,
         allow_move   = true,
         efficiency   = possible_efficiencies[math.random(1, #possible_efficiencies)],
         orientation  = orientation,
         attached     = {},
         attached_to  = nil,
         subordinated = {},
         managed_by   = data.managed_by,
      },
      drawing = {
        fn          = nil,
        mouse_click = nil,
        mouse_move  = nil,
      },
   }
   setmetatable(o, Unit)
   o:_update_state(data.state)
   o:_update_layer()
   tile:set_unit(o, o.data.layer)
   o:refresh()
   table.insert(player.units, o)
   return o
end

function Unit:_update_layer()
   local unit_type = self.definition.unit_type.id
   local layer = self.data.state == 'flying' and 'air' or 'surface'
   self.data.layer = layer
end

function Unit:_update_state(new_state)
   self.data.state = new_state
   local united_staff = self:_united_staff()
   for idx, weapon_instance in pairs(united_staff) do
      weapon_instance:update_state(new_state)
   end
end

function Unit:get_movement_layer()
   local unit_type = self.definition.unit_type.id
   return (unit_type == 'ut_air') and 'air' or 'surface'
end

function Unit:get_layer() return self.data.layer end

function Unit:bind_ctx(context)
  local x = context.tile.virtual.x + context.screen.offset[1]
  local y = context.tile.virtual.y + context.screen.offset[2]
  local terrain = self.engine.map.terrain

  local hex_w = context.tile_geometry.w
  local hex_h = context.tile_geometry.h
  local hex_x_offset = context.tile_geometry.x_offset

  local magnet_to = context.unit[self.id].magnet_to or 'center'
  local size = context.unit[self.id].size

  local image = self.definition:get_icon(self.data.state)
  local scale = (size == 'normal') and 1.0 or 0.6
  local x_shift = (hex_w - image.w * scale)/2
  local y_shift = (magnet_to == 'center')
            and (hex_h - image.h*scale)/2
            or (magnet_to == 'top')
            and 0                         -- pin unit to top
            or (hex_h - image.h*scale)    -- pin unit to bottom

  local dst = {
    x = math.modf(x + x_shift),
    y = math.modf(y + y_shift),
    w = math.modf(image.w * scale),
    h = math.modf(image.h * scale),
  }
  local orientation = self.data.orientation
  assert((orientation == 'left') or (orientation == 'right'), "Unknown unit orientation: " .. orientation)
  local flip = (orientation == 'left') and SDL.rendererFlip.none or
  (orientation == 'right') and SDL.rendererFlip.Horizontal

  -- unit nation flag
  local unit_flag = self.definition.nation.unit_flag
  -- +/- 1 is required to narrow the clickable/hilightable area
  -- which is also needed to preven hilighting when mouse pointer
  -- will be moved to the bottom tile
  local unit_flag_region = Region.create(x + 1 + hex_x_offset - unit_flag.w, y + 1 + hex_h - unit_flag.h, x - 1 + hex_x_offset, y - 1 + hex_h)
  local unit_flag_dst =  {
    x = x + hex_x_offset - unit_flag.w,
    y = y + hex_h - unit_flag.h,
    w = unit_flag.w,
    h = unit_flag.h,
  }
  local unit_flag_hilight_image = self.engine.renderer.theme.unit_flag_hilight
  local do_hilight_unit_flag = false
  local update_unit_flag = function(x, y)
    do_hilight_unit_flag =  unit_flag_region:is_over(x, y)
    return do_hilight_unit_flag
  end
  update_unit_flag(context.mouse.x, context.mouse.y)

  -- unit state
  local size = self.definition.data.size
  local efficiency = self.data.efficiency
  local unit_state = self.engine.renderer.theme:get_unit_state_icon(size, efficiency)

  -- change attack possibility
  local change_attack
  local change_attack_region
  local attack_kinds
  local attack_kind_idx = 1
  local is_over_change_attack_icon = function(x, y)
    return change_attack and change_attack_region:is_over(x, y)
  end

  local u = context.state.selected_unit
  if (u and context.state.active_tile.id == self.tile.id) then
    local actions_map = u.data.actions_map
    if (actions_map and actions_map.attack[self.tile.id]) then
      attack_kinds = u:get_attack_kinds(self.tile)
      if (#attack_kinds > 1) then
        local icon = context.renderer.theme.change_attack_type.available
        local change_attack_x = x + (hex_w - hex_x_offset)
        change_attack = {
          icon = icon,
          dst = {
            x = change_attack_x,
            y = y,
            w = icon.w,
            h = icon.h,
          },
        }
        change_attack_region = Region.create(change_attack_x, y, change_attack_x + icon.w, y + icon.h)
        local icon_kind = is_over_change_attack_icon(context.mouse.x, context.mouse.y)
          and 'hilight' or 'available'
        change_attack.icon = context.renderer.theme.change_attack_type[icon_kind]
      end
    end
  end


  local sdl_renderer = assert(context.renderer.sdl_renderer)
  self.drawing.fn = function()
    -- draw selection frame
    if (context.state.selected_unit and context.state.selected_unit.id == self.id) then
      local frame = terrain:get_icon('frame')
      assert(sdl_renderer:copy(frame.texture, nil, {x = x, y = y, w = hex_w, h = hex_h}))
    end

    -- draw unit
    assert(sdl_renderer:copyEx({
      texture     = image.texture,
      source      = {x = 0 , y = 0, w = image.w, h = image.h},
      destination = dst,
      nil,                                          -- no angle
      nil,                                          -- no center
      flip        = flip,
    }))

    -- draw unit nation flag
    assert(sdl_renderer:copy(unit_flag.texture, nil, unit_flag_dst))
    if (do_hilight_unit_flag) then
      assert(sdl_renderer:copy(unit_flag_hilight_image.texture, nil, unit_flag_dst))
    end

    -- draw unit state
    assert(sdl_renderer:copy(
      unit_state.texture,
      nil,
      {
        x = x + (hex_w - hex_x_offset),
        y = y + hex_h - unit_state.h,
        w = unit_state.w,
        h = unit_state.h,
      }
    ))

    -- draw unit change attack icon
    if (change_attack) then
      assert(sdl_renderer:copy(
        change_attack.icon.texture,
        nil,
        change_attack.dst
      ))
    end


  end

  local mouse_click = function(event)
    if ((event.tile_id == self.tile.id) and (event.button == 'left')) then
      -- check if the click has been performed on unit flag, then
      -- show unit info
      if (unit_flag_region:is_over(event.x, event.y)) then
        self.engine.interface:add_window('unit_info_window', self)
        return true
      end
      -- may be we click on other unit to select it
      if (context.state.action == 'default') then
        if (is_over_change_attack_icon(event.x, event.y)) then
          attack_kind_idx = attack_kind_idx + 1
          if (attack_kind_idx > #attack_kinds) then attack_kind_idx = 1 end
          local action = attack_kinds[attack_kind_idx]
          self.engine.state.action = action
          return true
        elseif (self.engine.current_player == self.player) then
          context.state.selected_unit = self
          print("selected unit " .. self.id)
          self:update_actions_map()
          self.engine.mediator:publish({ "view.update" })
          return true
        end
      else
        local action = context.state.action
        local actor = assert(context.state.selected_unit, "no selected unit for action " .. action)
        local method_for = {
          merge              = 'merge_at',
          battle             = 'attack_on',
          ["fire/artillery"] = 'attack_on'
        }
        -- method might be absent in the case, when we move air unit into the
        -- tile, occupied by other unit. Then unitst do not interact, and
        -- action will be performed by underlying tile
        local method = method_for[action]
        if (method) then
          actor[method](actor, self.tile, action)
          return true
        end
      end
    end
  end

  local update_action = function(tile_id, x, y)
    if (tile_id == self.tile.id) then
      local action = 'default'
      local u = context.state.selected_unit
      local actions_map = u and u.data.actions_map
      local hint = self.name
      if (actions_map and actions_map.merge[tile_id]) then
        action = 'merge'
      elseif (actions_map and actions_map.attack[tile_id]) then
        action = attack_kinds[attack_kind_idx]
      elseif (actions_map and actions_map.move[tile_id]) then
        -- will be processed by tile
        if (self:get_layer() ~= u:get_movement_layer()) then
          return false
        end
      end
      self.engine.state.action = action

      -- update attack kind possibility
      if (change_attack) then
        local is_over = is_over_change_attack_icon(x, y)
        local icon_kind = is_over and 'hilight' or 'available'
        if (is_over) then
          action = 'default'
          hint   = self.engine:translate('map.change-attack-kind')
        end
        change_attack.icon = context.renderer.theme.change_attack_type[icon_kind]
      end
      if (update_unit_flag(x, y)) then
        action = 'default'
        hint   = self.engine:translate('map.unit_info')
      end

      self.engine.state.action = action
      self.engine.state.mouse_hint = hint
      -- print("move mouse over " .. tile_id .. ", action: "  .. action)
      return true
    else
      -- remove unit flag hilight
      update_unit_flag(x, y)
    end
  end

  local mouse_move = function(event)
    return update_action(event.tile_id, event.x, event.y)
  end

  update_action(context.state.active_tile.id, context.mouse.x, context.mouse.y)

  context.events_source.add_handler('mouse_click', mouse_click)
  context.events_source.add_handler('mouse_move', mouse_move)

  self.drawing.mouse_click = mouse_click
  self.drawing.mouse_move  = mouse_move
end

function Unit:unbind_ctx(context)
  context.events_source.remove_handler('mouse_click', self.drawing.mouse_click)
  context.events_source.remove_handler('mouse_move', self.drawing.mouse_move)
  self.drawing.fn = nil
  self.drawing.mouse_click = nil
end

function Unit:draw()
  self.drawing.fn()
end

-- returns list of weapon instances for the current unit as well as for all it's attached units
function Unit:_united_staff()
   local unit_list = self:_all_units()

   local united_staff = {}
   for idx, unit in pairs(unit_list) do
      for idx2, weapon_instance in pairs(unit.data.staff) do
         table.insert(united_staff, weapon_instance)
      end
   end
   return united_staff
end

-- returns list of all units, i.e. self + attached
function Unit:_all_units()
  local unit_list = {self}
  for idx, unit in pairs(self.data.attached) do table.insert(unit_list, unit) end
  return unit_list
end

-- retunrs a table of weapon instances, which are will be marched,
-- i.e. as if they already packed into transporters
-- includes attached units too.
function Unit:_marched_weapons()
   local list = {}

   local united_staff = self:_united_staff()
   -- k:  type of weapon movement, which are capable to transport, w: quantity
   local transport_for = {}

   -- pass 1: determine transport capabilites
   for idx, weapon_instance in pairs(united_staff) do
      local transport_capability, value = weapon_instance:is_capable('TRANSPORTS_%w+')
      if (value == 'TRUE') then
         local transport_kind = string.lower(string.gsub(transport_capability, 'TRANSPORTS_', ''))
         local prev_value = transport_for[transport_kind] or 0
         transport_for[transport_kind] = prev_value + weapon_instance:quantity()
      end
   end

   -- pass 2: put into transpots related weapons
   for idx, weapon_instance in pairs(united_staff) do
      local kind = weapon_instance.weapon.movement_type
      local transported = false
      local quantity = weapon_instance:quantity()
      if ((quantity  > 0) and (transport_for[kind] or 0) >= quantity) then
         transported = true
         transport_for[kind] = transport_for[kind] - quantity
      end
      if (not transported) then table.insert(list, weapon_instance) end
   end
   return list
end


function Unit:refresh()
   local result = {}
   self.data.allow_move = true
   for idx, weapon_instance in pairs(self:_united_staff()) do
      weapon_instance:refresh()
   end
end


-- returns table (k: weapon_instance_id, v: value) of available movements for all
-- marched weapons instances
function Unit:available_movement()
   local data = {}
   local allow_move = self.data.allow_move
   for idx, weapon_instance in pairs(self:_marched_weapons()) do
      data[weapon_instance.id] = allow_move and weapon_instance.data.movement or 0
   end
   return data
end

-- returns table (k: weapon_instance_id, v: movement cost) for all marched weapon instances
function Unit:move_cost(tile)
   local weather = self.engine:current_weather()
   local cost_for = tile.data.terrain_type.move_cost
   local costs = {} -- k: weapon id, v: movement cost
   for idx, weapon_instance in pairs(self:_marched_weapons()) do
      local movement_type = weapon_instance.weapon.movement_type
      local value = cost_for[movement_type][weather]
      if (value == 'A') then value = weapon_instance.weapon.data.movement -- all movement points
      elseif (value == 'X') then value = math.maxinteger end              -- impassable
      costs[weapon_instance.id] = value
   end
   return Vector.create(costs)
end

function Unit:_update_orientation(dst_tile, src_tile)
   local dx = dst_tile.data.x - src_tile.data.x
   local orientation = self.data.orientation
   if (dx > 0) then orientation = 'right'
   elseif (dx <0) then orientation = 'left' end

   -- print("orientation: " .. self.data.orientation .. " -> " .. orientation)
   self.data.orientation = orientation
end

function Unit:_check_death()
  local alive_weapons = 0
  for k, weapon_instance in pairs(self.data.staff) do
    alive_weapons = alive_weapons + weapon_instance.data.quantity
  end
  if (alive_weapons == 0) then
    self.data.state = 'dead'
    print(self.id .. " is dead " .. alive_weapons)
    if (self.tile) then
      self.tile:set_unit(nil, self.data.layer)
      self.tile = nil
      if (self.engine.state.selected_unit == self) then
          self.engine.state.selected_unit = nil
      end
      self.engine.mediator:publish({ "model.update" })
    end
  end
end

function Unit:_detach()
  if (self.data.attached_to) then
    local parent = self.data.attached_to
    local idx
    for i, u in ipairs(parent.data.attached) do
      if (u == self) then
        idx = i
        break
      end
    end
    assert(idx)
    table.remove(parent.data.attached, idx)
    self.data.attached_to = nil
    self.tile = parent.tile
    return true
  end
end

function Unit:move_to(dst_tile)
  -- print("moving " .. self.id .. " to " .. dst_tile.id)
  -- print("move map = " .. inspect(self.data.actions_map.move))
  local costs = assert(self.data.actions_map.move[dst_tile.id],
    "unit " .. self.id  .. " cannot move to ".. dst_tile.id)
  local being_attached = self:_detach()
  local src_tile = self.tile

  -- calculate back route from dst_tile to src_tile
  -- print(inspect(self.data.actions_map.move))
  local route = { dst_tile }
  local marched_weapons = self:_marched_weapons()
  local move_costs = self.data.actions_map.move
  local initial_costs = {}
  for idx, wi in pairs(marched_weapons) do initial_costs[wi.id] = 0 end
  move_costs[src_tile.id] = Vector.create(initial_costs)

  local get_prev_tile = function()
    local current_tile = dst_tile
    local iterator = function(state, value)
      if (current_tile ~= src_tile) then
        local min_tile = nil
        local min_cost = math.huge
        for adj_tile in self.engine:get_adjastent_tiles(current_tile) do
          local costs = move_costs[adj_tile.id]
          -- print("costs = " .. inspect(costs))
          if (costs and costs:min() < min_cost) then
            min_tile = adj_tile
            min_cost = costs:min()
          end
        end
        assert(min_tile)
        current_tile = min_tile
        -- print("prev tile " .. min_tile.id)
        return (min_tile ~= src_tile) and min_tile or nil
      end
    end
    return iterator, nil, true
  end

  for tile in get_prev_tile() do
    table.insert(route, 1, tile)
  end
  -- print("routing via " .. inspect(_.map(route, function(k, v) return v.id end)))

  local prev_tile = src_tile
  for idx, tile in pairs(route) do
    -- print(self.id .. " moves on " .. tile.id .. " from " .. prev_tile.id)
    -- TODO: check for ambush and mines
    local ctx = {
      unit_id  = self.id,
      dst_tile = tile.id,
      src_tile = prev_tile.id,
    }
    self.engine.history:record_player_action('unit/move', ctx, true, {})
    prev_tile = tile
  end
  dst_tile = prev_tile
  -- print("history = " .. inspect(self.engine.history.records_at))

  self.data.allow_move = not(self:_enemy_near(dst_tile)) and not(self:_enemy_near(src_tile))
  if (not being_attached) then src_tile:set_unit(nil, self.data.layer) end
  -- print(inspect(costs))
  for idx, weapon_instance in pairs(marched_weapons) do
    local cost = costs.data[weapon_instance.id]
    weapon_instance.data.movement = weapon_instance.data.movement - cost
  end

  -- update state

  local unit_type = self.definition.unit_type.id
  local new_state
  if (unit_type == 'ut_land') then
    new_state = self:_enemy_near(dst_tile) and 'defending' or 'marching'
  elseif (unit_type == 'ut_air') then
    new_state = 'flying'
  end
  self:_update_state(new_state)
  self:_update_layer()

  dst_tile:set_unit(self, self.data.layer)
  self.tile = dst_tile
  self:_update_orientation(dst_tile, src_tile)
  self:update_actions_map()
  self.engine.mediator:publish({ "view.update" })
end

function Unit:merge_at(dst_tile)
   local layer = self.data.layer
   local other_unit = assert(dst_tile:get_unit(layer))
   self:move_to(dst_tile)

   local weight_for = {
      L = 100,
      M = 10,
      S = 1,
   }
   local my_weight    = weight_for[self.definition.data.size]
   local other_weight = weight_for[other_unit.definition.data.size]
   local core_unit, aux_unit
   if (my_weight > other_weight) then
      core_unit, aux_unit = self, other_unit
   else
      core_unit, aux_unit = other_unit, self
   end

   for idx, unit in pairs(aux_unit.data.attached) do
      table.remove(aux_unit.data.attached)
      table.insert(core_unit.data.attached, unit)
   end
   table.insert(core_unit.data.attached, aux_unit)

   -- aux unit is now attached, remove from map
   aux_unit.tile:set_unit(nil, layer)
   aux_unit.tile = nil
   aux_unit.data.attached_to = core_unit
   dst_tile:set_unit(core_unit, layer)

   self.engine.state.selected_unit = core_unit
   core_unit:update_actions_map()
   self.engine.mediator:publish({ "view.update" })
end

function Unit:land_to(tile)
   self:move_to(tile)
   self:_update_state('landed')
   self:_update_layer()
   self.data.allow_move = false
   self:update_actions_map()
   self.engine.mediator:publish({ "view.update" })
end

function Unit:attack_on(tile, fire_type)
  self:_check_death()
  local enemy_unit = tile:get_any_unit(self.engine.active_layer)
  assert(enemy_unit)
  self:_update_orientation(enemy_unit.tile, self.tile)
  local i_casualities, p_casualities, i_participants, p_participants
    = self.engine.battle_scheme:perform_battle(self, enemy_unit, fire_type)

  local unit_serializer = function(key, unit)
    return {
      unit_id = unit.id,
      state   = unit.data.state,
    }
  end

  local ctx = {
    i_units   = _.map(self:_all_units(), unit_serializer),
    p_units   = _.map(enemy_unit:_all_units(), unit_serializer),
    fire_type = fire_type,
    tile      = tile.id,
  }
  local results = {
    i = { casualities = i_casualities, participants = i_participants },
    p = { casualities = p_casualities, participants = p_participants },
  }
  self.engine.history:record_player_action('battle', ctx, true, results)
  print("batte results = " .. inspect(results))

  self:_check_death()
  enemy_unit:_check_death()
  if (self.data.state ~= 'dead') then
    self:update_actions_map()
  end
end


function Unit:_enemy_near(tile)
   local layer = self:get_movement_layer()
   for adj_tile in self.engine:get_adjastent_tiles(tile) do
      local enemy = adj_tile:get_unit(layer)
      local has_enemy = enemy and enemy.player ~= self.player
      if (has_enemy) then return true end
   end
   return false
end


function Unit:update_actions_map()
   local engine = self.engine
   local map = engine.map
   -- determine, what the current user can do at the visible area
   local actions_map = {}
   local start_tile = self.tile or self.data.attached_to.tile
   assert(start_tile)


   local merge_candidates = {}
   local landing_candidates = {}

   local layer = self:get_movement_layer()
   local unit_type = self.definition.unit_type.id

   local get_move_map = function()
      local inspect_queue = {}
      local add_reachability_tile = function(src_tile, dst_tile, cost)
         table.insert(inspect_queue, {to = dst_tile, from = src_tile, cost = cost})
      end
      local marched_weapons = self:_marched_weapons()

      local get_nearest_tile = function()
         local iterator = function(state, value) -- ignored
            if (#inspect_queue > 0) then
               -- find route to a hex with smallest cost
               local min_idx, min_cost = 1, inspect_queue[1].cost:min()
               for idx = 2, #inspect_queue do
                  if (inspect_queue[idx].cost:min() < min_cost) then
                     min_idx, min_cost = idx, inspect_queue[idx].cost:min()
                  end
               end
               local node = inspect_queue[min_idx]
               local src, dst = node.from, node.to
               table.remove(inspect_queue, min_idx)
               -- remove more costly destionations
               for idx, n in ipairs(inspect_queue) do
                  if (n.to == dst) then table.remove(inspect_queue, idx) end
               end
               return src, dst, node.cost
            end
         end
         return iterator, nil, true
      end

      -- initialize reachability with tile, on which the unit is already located
      local initial_costs = {}
      for idx, wi in pairs(marched_weapons) do initial_costs[wi.id] = 0 end
      add_reachability_tile(start_tile, start_tile, Vector.create(initial_costs))


      local fuel_at = {};  -- k: tile_id, v: movement_costs table
      local fuel_limit = Vector.create(self:available_movement())
      for src_tile, dst_tile, costs in get_nearest_tile() do
         local other_unit = dst_tile:get_unit(layer)

         -- inspect for further merging
         if (other_unit and other_unit.player == self.player) then
            table.insert(merge_candidates, dst_tile)
         end
         -- inspect for further landing
         if (unit_type == 'ut_air' and dst_tile.data.terrain_type.id == 'a') then
            table.insert(landing_candidates, dst_tile)
         end

         local can_move = not (other_unit and other_unit.player ~= self.player and other_unit:get_layer() == layer)
         if (can_move) then
            -- print(string.format("%s -> %s : %d", src_tile.id, dst_tile.id, cost))
            fuel_at[dst_tile.id] = costs
            local has_enemy_near = self:_enemy_near(dst_tile)
            for adj_tile in engine:get_adjastent_tiles(dst_tile, fuel_at) do
               local adj_cost = self:move_cost(adj_tile)
               local total_costs = costs + adj_cost
               -- ignore near enemy, if we are moving from the start tile
               if (dst_tile == start_tile) then has_enemy_near = false end
               if (total_costs <= fuel_limit and not has_enemy_near) then
                  add_reachability_tile(dst_tile, adj_tile, total_costs)
               end
            end
         end
      end
      -- do not move on the tile, where unit is already located
      fuel_at[start_tile.id] = nil
      return fuel_at
   end

   local get_attack_map = function()
      local attack_map = {}
      local visited_tiles = {} -- cache

      local max_range = -1
      local weapon_capabilites = {} -- k1: layer, value: table with k2:range, and value: list of weapons
      local united_staff = self:_united_staff()
      for idx, weapon_instance in pairs(united_staff) do
         if (weapon_instance.data.can_attack) then
            for layer, range in pairs(weapon_instance.weapon.data.range) do
               -- we use range +1 to avoid zero-based indices
               for r = 0, range do
                  local layer_capabilites = weapon_capabilites[layer] or {}
                  local range_capabilites = layer_capabilites[r + 1] or {}
                  table.insert(range_capabilites, weapon_instance)
                  -- print("rc = " .. inspect(range_capabilites))
                  layer_capabilites[r + 1] = range_capabilites
                  weapon_capabilites[layer] = layer_capabilites
               end

               if (max_range < range) then max_range = range end
            end
         end
      end
      -- print("wc: " .. inspect(weapon_capabilites))
      -- print("wc: " .. inspect(weapon_capabilites.surface[1]))


      local get_fire_kinds = function(weapon_instance, distance, enemy_unit)
         local fire_kinds = {}
         local enemy_layer = enemy_unit:get_layer()
         local same_layer = (enemy_layer == layer)
         if (weapon_instance:is_capable('RANGED_FIRE') and same_layer) then
            table.insert(fire_kinds, 'fire/artillery')
         end
         if ((distance == 1) and same_layer) then
            table.insert(fire_kinds, 'battle')
         end
         if (not same_layer) then
            table.insert(fire_kinds, ((layer == 'surface')
                               and 'fire/anti-air'
                               or  'fire/bombing'
                                     )
            )
         end
         if ((distance == 0) and (enemy_layer == layer)) then
            table.insert(fire_kinds, 'battle')
         end
         return fire_kinds
      end

      local examine_queue = {}
      local already_added = {}
      local add_to_queue = function(tile)
         if (not already_added[tile.id]) then
            table.insert(examine_queue, tile)
            already_added[tile.id] = true
         end
      end

      add_to_queue(start_tile)
      while (#examine_queue > 0) do
         local tile = table.remove(examine_queue, 1)
         local distance = start_tile:distance_to(tile)
         visited_tiles[tile.id] = true

         local enemy_units = tile:get_all_units(function(unit) return unit.player ~= self.player end)
         for idx, enemy_unit in pairs(enemy_units) do
            local enemy_layer = enemy_unit:get_layer()
            local weapon_instances = (weapon_capabilites[enemy_layer] or {})[distance+1]
            if (weapon_instances) then
               local attack_details = attack_map[tile.id] or {}
               local layer_attack_details = attack_details[enemy_layer] or {}
               for k, weapon_instance in pairs(weapon_instances) do
                  local fire_kinds = get_fire_kinds(weapon_instance, distance, enemy_unit)
                  -- print(inspect(fire_kinds))
                  for k, fire_kind in pairs(fire_kinds) do
                     -- print(fire_kind .. " by " .. weapon_instance.id)
                     local fired_weapons = layer_attack_details[fire_kind] or {}
                     table.insert(fired_weapons, weapon_instance.id)
                     table.sort(fired_weapons)
                     layer_attack_details[fire_kind] = fired_weapons
                  end
               end
               attack_details[enemy_layer] = layer_attack_details
               attack_map[tile.id] = attack_details
            end
         end
         for adj_tile in engine:get_adjastent_tiles(tile, visited_tiles) do
            local distance = start_tile:distance_to(adj_tile)
            if (distance <= max_range) then
               add_to_queue(adj_tile)
            end
         end
      end

      return attack_map
   end

   local get_merge_map = function()
      local merge_map = {}
      local my_size = self.definition.data.size
      local my_attached = self.data.attached
      local my_unit_type = self.definition.unit_type.id
      for k, tile in pairs(merge_candidates) do
         local other_unit = tile:get_unit(layer)
         if (other_unit.definition.unit_type.id == my_unit_type) then
            local expected_quantity = 1 + 1 + #my_attached + #other_unit.data.attached
            local other_size = other_unit.definition.data.size
            local size_matches = my_size ~= other_size
            local any_manager = self:is_capable('MANAGE_LEVEL') or other_unit:is_capable('MANAGE_LEVEL')
            if (expected_quantity <= 3 and size_matches and not any_manager) then
               merge_map[tile.id] = true
               -- print("m " .. tile.id .. ":" .. my_size .. other_size)
            end
         end
      end
      return merge_map
   end

   local get_landing_map = function()
      local map = {}
      for idx, tile in pairs(landing_candidates) do
         if (tile ~= start_tile) then
            map[tile.id] = true
         end
      end
      return map
   end

   actions_map.move    = get_move_map()
   actions_map.merge   = get_merge_map()
   actions_map.landing = get_landing_map()
   actions_map.attack  = get_attack_map()

   self.data.actions_map = actions_map
   self.engine.mediator:publish({ "view.update" });

   -- print(inspect(actions_map.move))
end

function Unit:is_capable(flag_mask)
   return self.definition:is_capable(flag_mask)
end

function Unit:get_subordinated(recursively)
   local r = {}
   local get_subordinated
   get_subordinated = function(u)
      for idx, s_unit in pairs(u.data.subordinated) do
         table.insert(r, s_unit)
         if (recursively) then get_subordinated(s_unit) end
      end
   end
   get_subordinated(self)
   return r
end


function Unit:subordinate(subject)
   local k, manage_level = self:is_capable('MANAGE_LEVEL')
   assert(manage_level, "unit " .. self.id .. " isn't capable to manage")
   manage_level = tonumber(manage_level)
   local k, subject_manage_level = subject:is_capable('MANAGE_LEVEL')

   if (not subject_manage_level) then -- subordinate usual (non-command) unit
      local k, units_limit = self:is_capable('MANAGED_UNITS_LIMIT')
      local k, unit_sizes_limit = self:is_capable('MANAGED_UNIT_SIZES_LIMIT')
      if (units_limit ~= 'unlimited') then
         local total_subjects = #self.data.subordinated
         assert(total_subjects < tonumber(units_limit),
                "not able to subordinate " .. subject.id .. ": already have " .. total_subjects)
      end
      if (unit_sizes_limit ~= 'unlimited') then
         local total_subjects = 0
         for k, unit in pairs(self.data.subordinated) do
            if (unit.definition.size == subject.definition.data.size) then
               total_subjects = total_subjects + 1
            end
         end
         assert(total_subjects < tonumber(unit_sizes_limit),
                "not able to subordinate " .. subject.id .. ": already have " .. total_subjects
                 .. "of size " .. subject.definition.data.size
         )
      end
      -- all OK, can subordinate
      table.insert(self.data.subordinated, subject)
      print("unit " .. subject.id .. " managed by " .. self.id)
   else -- subordinate command unit (manager)
      subject_manage_level = tonumber(subject_manage_level)
      assert(subject_manage_level > manage_level)

      local k, managed_managers_level_limit = self:is_capable('MANAGED_MANAGERS_LEVEL_LIMIT')

      if (managed_managers_level_limit ~= 'unlimited') then
         local total_subjects = 0
         managed_managers_level_limit = tonumber(managed_managers_level_limit)
         for k, unit in pairs(self.data.subordinated) do
            local k, unit_manage_level = subject:is_capable('MANAGE_LEVEL')
            if (unit_manage_level) then
               unit_manage_level = tonumber(unit_manage_level)
               if (unit_manage_level == subject_manage_level) then
                  total_subjects = total_subjects + 1
               end
            end
         end
         assert(total_subjects < managed_managers_level_limit,
                "not able to subordinate " .. subject.id .. ": already have " .. total_subjects
                   .. " manager units of level " .. subject_manage_level
         )
      end

      -- all, OK, can subordinate
      table.insert(self.data.subordinated, subject)
      print("manager unit " .. subject.id .. " managed by " .. self.id)
   end
end

function Unit:get_attack_kinds(tile)
   local kinds

   local attack_layers = self.data.actions_map.attack[tile.id]
   local same_layer = self:get_layer()
   local opposite_layer = (same_layer == 'surface') and 'air' or 'surface'
   local attack_layer = attack_layers[same_layer]
   if (not attack_layer) then                         -- non ambigious case
      attack_layer = attack_layers[opposite_layer]
      if (attack_layer['fire/bombing']) then kind = {'fire/bombing'}
      elseif (attack_layer['fire/anti-air']) then kind = {'fire/anti-air'}
      else
         error("possible attack kinds for different layers are: 'fire/bombing' or 'fire/anti-air'")
      end
   else                                               -- ambigious case
      local selected_attack, attack_score = nil, 0
      kinds = {}
      if (attack_layer['battle']) then table.insert(kinds, 'battle') end
      if (attack_layer['fire/artillery']) then
        local position = (self.definition.unit_class.id == 'art') and 1 or #kinds + 1
        table.insert(kinds, position, 'fire/artillery')
      end
   end
   return kinds
end

function Unit:change_orientation()
  local o = (self.data.orientation == 'left') and 'right' or 'left'
  self.data.orientation = o
  self.engine.mediator:publish({ "view.update" })
end

return Unit
