-- LX49+ GUI Mapper for REAPER
-- Native ReaScript/gfx GUI + JSFX gmem bridge.
-- Author: generated prototype for Nat Chbret
-- Install the companion JSFX: LX49plus_CC_Bridge.jsfx

local SECTION = "LX49plus_GUI_Mapper"
local GMEM_NAME = "LX49_CC_BRIDGE"
local SLOTS, STRIDE, BASE = 256, 4, 16

reaper.gmem_attach(GMEM_NAME)
reaper.set_action_options(1) -- auto-terminate/relaunch if run again

gfx.init("LX49+ Mapper", 980, 620, 0, 80, 80)
gfx.setfont(1, "Arial", 15)

local W, H = 980, 620
local selected = 1
local learn_for = nil
local last_seq = math.floor(reaper.gmem_read(0) or 0)
local last_midi = "Aucun CC reçu"
local message = "Ajoute le JSFX bridge sur une piste armée, puis bouge un potard/fader."
local prev_mouse_down = false
local last_action_gate = {}
local controls = {}

local TARGET_ORDER = {
  "NONE",
  "SEL_VOL",
  "SEL_PAN",
  "TRACK_VOL",
  "TRACK_PAN",
  "MASTER_VOL",
  "TRACK_MUTE_TOGGLE",
  "TRACK_SOLO_TOGGLE",
  "TRACK_ARM_TOGGLE",
  "ACTION"
}

local TARGET_LABEL = {
  NONE = "Aucune",
  SEL_VOL = "Volume piste sélectionnée",
  SEL_PAN = "Pan piste sélectionnée",
  TRACK_VOL = "Volume piste N",
  TRACK_PAN = "Pan piste N",
  MASTER_VOL = "Volume master",
  TRACK_MUTE_TOGGLE = "Mute piste N",
  TRACK_SOLO_TOGGLE = "Solo piste N",
  TRACK_ARM_TOGGLE = "Arm piste N",
  ACTION = "Action REAPER"
}

local function add_control(kind, num, name, target, arg)
  controls[#controls + 1] = {
    id = #controls + 1,
    kind = kind,
    num = num,
    name = name,
    chan = nil,
    cc = nil,
    target = target or "NONE",
    arg = arg or 0,
    invert = false,
    min = 0,
    max = 127,
    last = -1
  }
end

for i = 1, 8 do add_control("FADER", i, "Fader " .. i, "TRACK_VOL", i) end
add_control("FADER", 9, "Fader 9", "MASTER_VOL", 0)
for i = 1, 8 do add_control("POT", i, "Potard " .. i, "TRACK_PAN", i) end
for i = 1, 8 do add_control("BUTTON", i, "Bouton " .. i, "TRACK_MUTE_TOGGLE", i) end
add_control("BUTTON", 9, "Bouton 9", "ACTION", 0)

local function split_lines(s)
  local t = {}
  for line in (s or ""):gmatch("[^\r\n]+") do t[#t + 1] = line end
  return t
end

local function split_pipe(s)
  local t = {}
  for part in (s .. "|"):gmatch("(.-)|") do t[#t + 1] = part end
  return t
end

local function save_mappings()
  local lines = {}
  for _, c in ipairs(controls) do
    lines[#lines + 1] = table.concat({
      c.id,
      c.chan or "",
      c.cc or "",
      c.target or "NONE",
      c.arg or 0,
      c.invert and 1 or 0,
      c.min or 0,
      c.max or 127
    }, "|")
  end
  reaper.SetExtState(SECTION, "mappings", table.concat(lines, "\n"), true)
end

local function load_mappings()
  local s = reaper.GetExtState(SECTION, "mappings")
  if not s or s == "" then return end
  for _, line in ipairs(split_lines(s)) do
    local p = split_pipe(line)
    local id = tonumber(p[1] or "")
    local c = id and controls[id]
    if c then
      c.chan = tonumber(p[2] or "")
      c.cc = tonumber(p[3] or "")
      c.target = p[4] ~= "" and p[4] or "NONE"
      local raw_arg = p[5] or "0"
      c.arg = tonumber(raw_arg) or raw_arg
      c.invert = tonumber(p[6] or "0") == 1
      c.min = tonumber(p[7] or "0") or 0
      c.max = tonumber(p[8] or "127") or 127
    end
  end
end
load_mappings()

local function clamp(x, a, b)
  if x < a then return a end
  if x > b then return b end
  return x
end

local function norm_from_cc(c, value)
  local mn = c.min or 0
  local mx = c.max or 127
  if mx == mn then mx = mn + 1 end
  local v = clamp((value - mn) / (mx - mn), 0, 1)
  if c.invert then v = 1 - v end
  return v
end

local function vol_from_norm(v)
  if v <= 0 then return 0 end
  -- Musical-ish curve: -60 dB to 0 dB.
  local db = -60 + (v * 60)
  return 10 ^ (db / 20)
end

local function get_track_by_one_based(n)
  n = tonumber(n or 0) or 0
  if n < 1 then return nil end
  return reaper.GetTrack(0, n - 1)
end

local function set_track_bool(tr, parm)
  if not tr then return end
  local cur = reaper.GetMediaTrackInfo_Value(tr, parm)
  reaper.SetMediaTrackInfo_Value(tr, parm, cur > 0 and 0 or 1)
  reaper.TrackList_AdjustWindows(false)
end

local function resolve_action_id(arg)
  if not arg then return 0 end
  local s = tostring(arg)
  local n = tonumber(s)
  if n and n > 0 then return n end
  if s:sub(1, 1) == "_" then
    local named = reaper.NamedCommandLookup(s)
    if named and named > 0 then return named end
  end
  return 0
end

local function apply_control(c, value)
  if c.target == "NONE" then return end
  local v = norm_from_cc(c, value)
  local tr

  if c.target == "SEL_VOL" then
    tr = reaper.GetSelectedTrack(0, 0)
    if tr then reaper.SetMediaTrackInfo_Value(tr, "D_VOL", vol_from_norm(v)) end

  elseif c.target == "SEL_PAN" then
    tr = reaper.GetSelectedTrack(0, 0)
    if tr then reaper.SetMediaTrackInfo_Value(tr, "D_PAN", (v * 2) - 1) end

  elseif c.target == "TRACK_VOL" then
    tr = get_track_by_one_based(c.arg)
    if tr then reaper.SetMediaTrackInfo_Value(tr, "D_VOL", vol_from_norm(v)) end

  elseif c.target == "TRACK_PAN" then
    tr = get_track_by_one_based(c.arg)
    if tr then reaper.SetMediaTrackInfo_Value(tr, "D_PAN", (v * 2) - 1) end

  elseif c.target == "MASTER_VOL" then
    tr = reaper.GetMasterTrack(0)
    if tr then reaper.SetMediaTrackInfo_Value(tr, "D_VOL", vol_from_norm(v)) end

  elseif c.target == "TRACK_MUTE_TOGGLE" then
    if value >= 64 and (last_action_gate[c.id] or 0) < 64 then set_track_bool(get_track_by_one_based(c.arg), "B_MUTE") end
    last_action_gate[c.id] = value

  elseif c.target == "TRACK_SOLO_TOGGLE" then
    if value >= 64 and (last_action_gate[c.id] or 0) < 64 then set_track_bool(get_track_by_one_based(c.arg), "I_SOLO") end
    last_action_gate[c.id] = value

  elseif c.target == "TRACK_ARM_TOGGLE" then
    if value >= 64 and (last_action_gate[c.id] or 0) < 64 then set_track_bool(get_track_by_one_based(c.arg), "I_RECARM") end
    last_action_gate[c.id] = value

  elseif c.target == "ACTION" then
    if value >= 64 and (last_action_gate[c.id] or 0) < 64 then
      local cmd = resolve_action_id(c.arg)
      if cmd > 0 then reaper.Main_OnCommand(cmd, 0) end
    end
    last_action_gate[c.id] = value
  end
end

local function process_midi(chan, cc, value)
  last_midi = string.format("Dernier MIDI : canal %d / CC %d / valeur %d", chan, cc, value)

  if learn_for then
    local c = controls[learn_for]
    if c then
      c.chan = chan
      c.cc = cc
      c.last = value
      message = string.format("%s appris : Ch %d CC %d", c.name, chan, cc)
      learn_for = nil
      save_mappings()
    end
  end

  for _, c in ipairs(controls) do
    if c.chan == chan and c.cc == cc then
      c.last = value
      apply_control(c, value)
    end
  end
end

local function poll_gmem()
  local write_seq = math.floor(reaper.gmem_read(0) or 0)
  if write_seq <= last_seq then return end
  local start_seq = last_seq + 1
  if write_seq - last_seq > SLOTS then start_seq = write_seq - SLOTS + 1 end

  for seq = start_seq, write_seq do
    local slot = BASE + ((seq % SLOTS) * STRIDE)
    local stored = math.floor(reaper.gmem_read(slot) or -1)
    if stored == seq then
      local chan = math.floor(reaper.gmem_read(slot + 1) or 0)
      local cc = math.floor(reaper.gmem_read(slot + 2) or -1)
      local value = math.floor(reaper.gmem_read(slot + 3) or 0)
      if chan >= 1 and chan <= 16 and cc >= 0 and cc <= 127 then process_midi(chan, cc, value) end
    end
  end
  last_seq = write_seq
end

local function cycle_target(c)
  local idx = 1
  for i, t in ipairs(TARGET_ORDER) do if t == c.target then idx = i break end end
  idx = idx + 1
  if idx > #TARGET_ORDER then idx = 1 end
  c.target = TARGET_ORDER[idx]
  if (c.target == "TRACK_VOL" or c.target == "TRACK_PAN" or c.target == "TRACK_MUTE_TOGGLE" or c.target == "TRACK_SOLO_TOGGLE" or c.target == "TRACK_ARM_TOGGLE") and (not c.arg or c.arg < 1) then
    c.arg = c.num or 1
  end
  save_mappings()
end

local function edit_target_arg(c)
  local label = "Valeur"
  local default = tostring(c.arg or "")
  if c.target:find("TRACK") then
    label = "Numéro de piste"
  elseif c.target == "ACTION" then
    label = "Command ID ou _ID SWS/custom"
  else
    message = "Cette cible n'a pas besoin d'argument."
    return
  end
  local ok, ret = reaper.GetUserInputs("Configurer " .. c.name, 1, label .. ",extrawidth=180", default)
  if ok then
    c.arg = ret
    save_mappings()
  end
end

local function edit_range(c)
  local ok, ret = reaper.GetUserInputs("Plage MIDI " .. c.name, 2, "Min MIDI,Max MIDI", tostring(c.min or 0) .. "," .. tostring(c.max or 127))
  if ok then
    local a, b = ret:match("([^,]+),([^,]+)")
    c.min = tonumber(a) or 0
    c.max = tonumber(b) or 127
    save_mappings()
  end
end

local function reset_selected(c)
  c.chan, c.cc, c.last = nil, nil, -1
  c.target = "NONE"
  c.arg = 0
  c.invert = false
  c.min, c.max = 0, 127
  save_mappings()
end

local function draw_text(txt, x, y, r, g, b, a)
  gfx.set(r or 1, g or 1, b or 1, a or 1)
  gfx.x, gfx.y = x, y
  gfx.drawstr(txt)
end

local function fill_rect(x, y, w, h, r, g, b, a)
  gfx.set(r, g, b, a or 1)
  gfx.rect(x, y, w, h, true)
end

local function stroke_rect(x, y, w, h, r, g, b, a)
  gfx.set(r, g, b, a or 1)
  gfx.rect(x, y, w, h, false)
end

local mouse_clicked = false
local mx, my = 0, 0

local function hit(x, y, w, h)
  return mouse_clicked and mx >= x and mx <= x + w and my >= y and my <= y + h
end

local function button(label, x, y, w, h)
  local hover = mx >= x and mx <= x + w and my >= y and my <= y + h
  fill_rect(x, y, w, h, hover and 0.25 or 0.18, hover and 0.28 or 0.20, hover and 0.34 or 0.24, 1)
  stroke_rect(x, y, w, h, 0.55, 0.62, 0.75, 1)
  draw_text(label, x + 8, y + 8, 0.95, 0.95, 0.95, 1)
  return hit(x, y, w, h)
end

local function control_label(c)
  local midi = c.cc and string.format("Ch%d CC%d", c.chan, c.cc) or "non appris"
  return c.name .. "\n" .. midi
end

local function draw_fader(c, x, y)
  local is_sel = selected == c.id
  fill_rect(x, y, 58, 230, is_sel and 0.18 or 0.12, is_sel and 0.22 or 0.14, is_sel and 0.30 or 0.18, 1)
  stroke_rect(x, y, 58, 230, is_sel and 0.95 or 0.45, is_sel and 0.75 or 0.50, is_sel and 0.25 or 0.55, 1)
  gfx.set(0.55, 0.58, 0.63, 1)
  gfx.line(x + 29, y + 42, x + 29, y + 170)
  local v = c.last >= 0 and c.last / 127 or 0
  local knob_y = y + 170 - (v * 128)
  fill_rect(x + 12, knob_y, 34, 16, 0.75, 0.78, 0.85, 1)
  draw_text(c.name, x + 6, y + 8, 1, 1, 1, 1)
  local midi = c.cc and string.format("C%d/%d", c.chan, c.cc) or "learn"
  draw_text(midi, x + 7, y + 192, 0.78, 0.83, 0.9, 1)
  if hit(x, y, 58, 230) then selected = c.id end
end

local function draw_pot(c, x, y)
  local is_sel = selected == c.id
  fill_rect(x, y, 82, 86, is_sel and 0.18 or 0.12, is_sel and 0.22 or 0.14, is_sel and 0.30 or 0.18, 1)
  stroke_rect(x, y, 82, 86, is_sel and 0.95 or 0.45, is_sel and 0.75 or 0.50, is_sel and 0.25 or 0.55, 1)
  local cx, cy = x + 41, y + 35
  gfx.set(0.72, 0.76, 0.84, 1)
  gfx.circle(cx, cy, 18, false)
  gfx.circle(cx, cy, 17, false)
  local v = c.last >= 0 and c.last / 127 or 0.5
  local ang = (-135 + v * 270) * math.pi / 180
  gfx.line(cx, cy, cx + math.cos(ang) * 16, cy + math.sin(ang) * 16)
  draw_text(c.name, x + 10, y + 62, 1, 1, 1, 1)
  if hit(x, y, 82, 86) then selected = c.id end
end

local function draw_pad_button(c, x, y)
  local is_sel = selected == c.id
  local active = c.last >= 64
  fill_rect(x, y, 82, 50, active and 0.32 or (is_sel and 0.18 or 0.12), active and 0.20 or (is_sel and 0.22 or 0.14), active and 0.16 or (is_sel and 0.30 or 0.18), 1)
  stroke_rect(x, y, 82, 50, is_sel and 0.95 or 0.45, is_sel and 0.75 or 0.50, is_sel and 0.25 or 0.55, 1)
  draw_text(c.name, x + 8, y + 8, 1, 1, 1, 1)
  local midi = c.cc and string.format("C%d/%d", c.chan, c.cc) or "learn"
  draw_text(midi, x + 8, y + 28, 0.78, 0.83, 0.9, 1)
  if hit(x, y, 82, 50) then selected = c.id end
end

local function draw_ui()
  W, H = gfx.w, gfx.h
  mx, my = gfx.mouse_x, gfx.mouse_y
  local down = (gfx.mouse_cap & 1) == 1
  mouse_clicked = down and not prev_mouse_down
  prev_mouse_down = down

  fill_rect(0, 0, W, H, 0.08, 0.09, 0.11, 1)
  draw_text("LX49+ Mapper pour REAPER", 24, 18, 1, 1, 1, 1)
  draw_text(last_midi, 24, 42, 0.75, 0.82, 0.95, 1)
  draw_text(message, 360, 42, 0.95, 0.85, 0.55, 1)

  -- Faders row
  local start_x = 24
  for i = 1, 9 do draw_fader(controls[i], start_x + (i - 1) * 68, 82) end

  -- Potards row
  for i = 1, 8 do draw_pot(controls[9 + i], 24 + (i - 1) * 96, 335) end

  -- Buttons row
  for i = 1, 9 do draw_pad_button(controls[17 + i], 24 + (i - 1) * 96, 448) end

  local c = controls[selected]
  local panel_x = 690
  fill_rect(panel_x, 82, 260, 230, 0.11, 0.12, 0.15, 1)
  stroke_rect(panel_x, 82, 260, 230, 0.38, 0.43, 0.55, 1)
  draw_text("Contrôle sélectionné", panel_x + 16, 98, 0.85, 0.9, 1, 1)
  draw_text(c.name, panel_x + 16, 124, 1, 1, 1, 1)
  draw_text(c.cc and string.format("MIDI : canal %d / CC %d", c.chan, c.cc) or "MIDI : non appris", panel_x + 16, 150, 0.82, 0.86, 0.93, 1)
  draw_text("Cible : " .. (TARGET_LABEL[c.target] or c.target), panel_x + 16, 176, 0.82, 0.86, 0.93, 1)
  local argtxt = tostring(c.arg or "")
  if c.target == "MASTER_VOL" or c.target == "SEL_VOL" or c.target == "SEL_PAN" or c.target == "NONE" then argtxt = "—" end
  draw_text("Argument : " .. argtxt, panel_x + 16, 202, 0.82, 0.86, 0.93, 1)
  draw_text(string.format("Plage : %d..%d%s", c.min or 0, c.max or 127, c.invert and " inversée" or ""), panel_x + 16, 228, 0.82, 0.86, 0.93, 1)

  if button(learn_for == c.id and "Bouge un CC..." or "Apprendre CC", panel_x + 16, 258, 110, 34) then
    learn_for = c.id
    message = "Bouge le potard/fader/bouton à associer à " .. c.name
  end
  if button("Changer cible", panel_x + 136, 258, 110, 34) then cycle_target(c) end

  fill_rect(panel_x, 330, 260, 185, 0.11, 0.12, 0.15, 1)
  stroke_rect(panel_x, 330, 260, 185, 0.38, 0.43, 0.55, 1)
  if button("Configurer argument", panel_x + 16, 348, 150, 34) then edit_target_arg(c) end
  if button("Inverser", panel_x + 176, 348, 70, 34) then c.invert = not c.invert; save_mappings() end
  if button("Plage min/max", panel_x + 16, 392, 150, 34) then edit_range(c) end
  if button("Reset", panel_x + 176, 392, 70, 34) then reset_selected(c) end
  if button("Sauver", panel_x + 16, 436, 110, 34) then save_mappings(); message = "Mappings sauvegardés dans l'ExtState REAPER." end
  if button("Stop", panel_x + 136, 436, 110, 34) then gfx.quit() end

  draw_text("Raccourci : clique un contrôle, Apprendre CC, bouge le contrôle physique.", 24, H - 42, 0.72, 0.76, 0.84, 1)
  draw_text("Pour les actions : configure un Command ID numérique ou un ID nommé commençant par _.", 24, H - 22, 0.72, 0.76, 0.84, 1)

  gfx.update()
end

local function main()
  poll_gmem()
  draw_ui()
  if gfx.getchar() >= 0 then
    reaper.defer(main)
  else
    reaper.gmem_attach("")
  end
end

main()
