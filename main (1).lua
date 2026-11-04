-- MELON SANDBOX 2D for LÖVE 11.x (touch + mouse)
-- Pick a tool on the bottom bar, then tap / drag in the arena.
-- GRAB drag stuff | GUN shoot (tap GUN again to change weapon) | BOOM explode
-- DELETE remove | SLOW slow motion | GRAV gravity | MELON/CRATE/BALL/BARREL/PLANK spawn | CLEAR wipe

local lg, lp = love.graphics, love.physics
local W, H = 960, 640
local GY = 520            -- ground height
local TB_Y = 540          -- toolbar top
local METER = 64
local STEP = 1 / 90

local sw, sh, scale, offx, offy = W, H, 1, 0, 0
local usedTouch = false
local world
local ragdolls, objects, bullets, pts, fxs = {}, {}, {}, {}, {}
local dmgQ, expQ = {}, {}
local pointers = {}
local tool, wi = "grab", 1
local slow, gravMode = false, 1
local acc, shake, groupCounter = 0, 0, 0
local juiceCanvas, bgCanvas
local fontS, fontM
local sfx, lastPlayed = {}, {}
local muted = false
local hintTime = 0
local turret = { left = 0, right = math.pi }

local function rnd(a, b) return a + math.random() * (b - a) end
local function inRect(px, py, x, y, w, h) return px >= x and px <= x + w and py >= y and py <= y + h end

local PALS = {
  { rind = {0.20, 0.58, 0.24}, stripe = {0.10, 0.38, 0.16}, flesh = {0.93, 0.18, 0.30}, juice = {0.95, 0.20, 0.30} }, -- watermelon
  { rind = {0.72, 0.86, 0.50}, stripe = {0.56, 0.72, 0.38}, flesh = {0.80, 0.95, 0.60}, juice = {0.75, 0.90, 0.50} }, -- honeydew
  { rind = {0.86, 0.66, 0.36}, stripe = {0.70, 0.50, 0.25}, flesh = {1.00, 0.55, 0.20}, juice = {1.00, 0.50, 0.15} }, -- cantaloupe
}

local WEAPONS = {
  { name = "PISTOL",  delay = 0.18, pellets = 1, spread = 0.01, speed = 1500, dmg = 30, dens = 6, kind = "bullet" },
  { name = "SHOTGUN", delay = 0.70, pellets = 7, spread = 0.14, speed = 1300, dmg = 14, dens = 3, kind = "bullet" },
  { name = "MINIGUN", delay = 0.05, pellets = 1, spread = 0.06, speed = 1500, dmg = 11, dens = 5, kind = "bullet" },
  { name = "ROCKET",  delay = 0.90, pellets = 1, spread = 0.00, speed = 650,  dmg = 10, dens = 8, kind = "rocket" },
}
local GRAVS = { { "EARTH", 1 }, { "MOON", 0.3 }, { "ZERO-G", 0 } }

local HINTS = {
  grab = "GRAB: drag things around and throw them",
  gun = "GUN: tap or hold to shoot. Tap GUN again to switch weapon",
  boom = "BOOM: tap anywhere to blow things up",
  delete = "DELETE: tap or drag over things to remove them",
  melon = "MELON: tap to drop a melon", crate = "CRATE: tap to drop a crate",
  ball = "BALL: tap to drop a bouncy ball", barrel = "BARREL: explodes when shot or smashed",
  plank = "PLANK: tap to drop a plank",
}

local BUTTONS = {
  { id = "grab", label = "GRAB", tool = true },
  { id = "gun", label = "GUN", tool = true },
  { id = "boom", label = "BOOM", tool = true },
  { id = "delete", label = "DELETE", tool = true },
  { id = "slow", label = "SLOW-MO" },
  { id = "grav", label = "GRAV" },
  { id = "melon", label = "MELON", tool = true },
  { id = "crate", label = "CRATE", tool = true },
  { id = "ball", label = "BALL", tool = true },
  { id = "barrel", label = "BARREL", tool = true },
  { id = "plank", label = "PLANK", tool = true },
  { id = "clear", label = "CLEAR" },
}
local function btnRect(i)
  local col, row = (i - 1) % 6, math.floor((i - 1) / 6)
  return col * 160 + 4, TB_Y + row * 50 + 3, 152, 44
end

---------------------------------------------------------------- view
local function updateScale()
  sw, sh = lg.getDimensions()
  scale = math.min(sw / W, sh / H)
  offx, offy = (sw - W * scale) / 2, (sh - H * scale) / 2
end
local function toV(x, y) return (x - offx) / scale, (y - offy) / scale end

---------------------------------------------------------------- sound
local function makeSound(f1, f2, dur, vol, noiseMix, wave)
  local rate = 22050
  local n = math.floor(rate * dur)
  local sd = love.sound.newSoundData(n, rate, 16, 1)
  local ph = 0
  for i = 0, n - 1 do
    local t = i / n
    ph = ph + (f1 + (f2 - f1) * t) / rate
    local tone
    if wave == "sine" then tone = math.sin(ph * 2 * math.pi)
    else tone = ((ph % 1) < 0.5) and 1 or -1 end
    local s = tone * (1 - noiseMix) + (math.random() * 2 - 1) * noiseMix
    sd:setSample(i, s * vol * (1 - t) ^ 2)
  end
  return love.audio.newSource(sd, "static")
end

local function initSounds()
  sfx.shoot  = makeSound(520, 120, 0.12, 0.22, 0.5)
  sfx.rocket = makeSound(200, 60, 0.30, 0.30, 0.6)
  sfx.boom   = makeSound(110, 25, 0.80, 0.55, 0.8)
  sfx.splat  = makeSound(240, 90, 0.10, 0.28, 0.85)
  sfx.pop    = makeSound(500, 160, 0.14, 0.30, 0.3, "sine")
  sfx.spawn  = makeSound(400, 800, 0.12, 0.20, 0, "sine")
  sfx.del    = makeSound(700, 200, 0.12, 0.20, 0.2, "sine")
end

local function play(name)
  if muted or not sfx[name] then return end
  local now = love.timer.getTime()
  if lastPlayed[name] and now - lastPlayed[name] < 0.05 then return end
  lastPlayed[name] = now
  pcall(function()
    local s = sfx[name]:clone()
    s:setPitch(rnd(0.9, 1.1))
    s:play()
  end)
end

---------------------------------------------------------------- juice / particles
local function stamp(fn)
  lg.push("all")
  lg.origin()
  lg.setCanvas(juiceCanvas)
  fn()
  lg.pop()
end

local function addPt(p)
  if #pts < 600 then pts[#pts + 1] = p end
end

local function sprayJuice(x, y, dx, dy, count, pal, power)
  local base = math.atan2(dy, dx)
  local omni = (dx == 0 and dy == 0)
  for _ = 1, count do
    local a = omni and rnd(0, math.pi * 2) or (base + rnd(-1.1, 1.1))
    local s = rnd(60, power)
    addPt({ kind = "juice", x = x, y = y, vx = math.cos(a) * s, vy = math.sin(a) * s - 40,
            life = rnd(0.6, 1.5), size = rnd(1.5, 4), col = pal.juice })
  end
end

local function spawnChunks(x, y, dx, dy, count, pal)
  local base = math.atan2(dy, dx)
  for _ = 1, count do
    local a = (dx == 0 and dy == 0) and rnd(0, math.pi * 2) or (base + rnd(-1.3, 1.3))
    local s = rnd(100, 380)
    addPt({ kind = "chunk", x = x, y = y, vx = math.cos(a) * s, vy = math.sin(a) * s - 80,
            rot = rnd(0, 6), vr = rnd(-12, 12), size = rnd(3, 7), life = 3,
            col = (math.random() < 0.5) and pal.rind or pal.flesh })
  end
  if count >= 2 then
    for _ = 1, 3 do
      local a = rnd(0, math.pi * 2)
      local s = rnd(60, 250)
      addPt({ kind = "seed", x = x, y = y, vx = math.cos(a) * s, vy = math.sin(a) * s - 100,
              life = 3, size = 2, col = {0.05, 0.05, 0.05} })
    end
  end
end

---------------------------------------------------------------- physics objects
local function newGroup()
  groupCounter = groupCounter - 1
  if groupCounter < -900 then groupCounter = -1 end
  return groupCounter
end

local function addPart(rag, kind, x, y, w, h, r, hp, dens)
  local body = lp.newBody(world, x, y, "dynamic")
  local shape = r and lp.newCircleShape(r) or lp.newRectangleShape(w, h)
  local fix = lp.newFixture(body, shape, dens)
  fix:setFriction(0.6)
  fix:setRestitution(0.15)
  fix:setGroupIndex(rag.group)
  body:setAngularDamping(1.2)
  body:setLinearDamping(0.05)
  local part = { type = "part", body = body, fixture = fix, kind = kind, w = w, h = h, r = r,
                 hp = hp, maxhp = hp, rag = rag, dead = false }
  fix:setUserData(part)
  body:setUserData(part)
  rag.parts[#rag.parts + 1] = part
  return part
end

local function removeRagdoll(rag)
  for _, p in ipairs(rag.parts) do
    p.gone = true
    if not p.body:isDestroyed() then p.body:destroy() end
  end
  for i, r in ipairs(ragdolls) do if r == rag then table.remove(ragdolls, i) break end end
end

local function removeObject(obj)
  obj.removed = true
  if not obj.body:isDestroyed() then obj.body:destroy() end
  for i, o in ipairs(objects) do if o == obj then table.remove(objects, i) break end end
end

local function createMelon(x, y)
  local rag = { parts = {}, group = newGroup(), pal = PALS[math.random(#PALS)], dead = false }
  local legL  = addPart(rag, "leg", x - 7, y + 36, 12, 32, nil, 32, 0.9)
  local legR  = addPart(rag, "leg", x + 7, y + 36, 12, 32, nil, 32, 0.9)
  local torso = addPart(rag, "torso", x, y, 26, 40, nil, 70, 1)
  local armL  = addPart(rag, "arm", x - 19, y - 6, 9, 28, nil, 30, 0.8)
  local armR  = addPart(rag, "arm", x + 19, y - 6, 9, 28, nil, 30, 0.8)
  local head  = addPart(rag, "head", x, y - 32, nil, nil, 15, 40, 1)
  local function join(a, b, ax, ay, lo, hi)
    local j = lp.newRevoluteJoint(a.body, b.body, ax, ay, false)
    j:setLimitsEnabled(true)
    j:setLimits(lo, hi)
    b.joint = j
  end
  join(torso, head, x, y - 21, -0.7, 0.7)
  join(torso, armL, x - 18, y - 19, -2.6, 2.6)
  join(torso, armR, x + 18, y - 19, -2.6, 2.6)
  join(torso, legL, x - 7, y + 21, -1.3, 1.3)
  join(torso, legR, x + 7, y + 21, -1.3, 1.3)
  ragdolls[#ragdolls + 1] = rag
  while #ragdolls > 25 do removeRagdoll(ragdolls[1]) end
  return rag
end

local function createProp(kind, x, y)
  local body = lp.newBody(world, x, y, "dynamic")
  local obj = { type = "obj", kind = kind, body = body }
  local shape, dens, rest = nil, 1, 0.1
  if kind == "crate" then
    local s = rnd(32, 60)
    obj.w, obj.h = s, s
    shape = lp.newRectangleShape(s, s); dens = 1.2
    obj.col = (math.random() < 0.5) and {0.62, 0.42, 0.22} or {0.5, 0.36, 0.2}
  elseif kind == "plank" then
    obj.w, obj.h = 130, 14
    shape = lp.newRectangleShape(130, 14); dens = 1
    obj.col = {0.78, 0.62, 0.38}
  elseif kind == "ball" then
    obj.r = rnd(16, 28)
    shape = lp.newCircleShape(obj.r); dens = 0.8; rest = 0.7
    local cols = { {0.2, 0.45, 0.9}, {0.9, 0.3, 0.25}, {0.95, 0.8, 0.2}, {0.6, 0.3, 0.8} }
    obj.col = cols[math.random(#cols)]
  elseif kind == "barrel" then
    obj.w, obj.h = 30, 46
    shape = lp.newRectangleShape(30, 46); dens = 1.1
    obj.col = {0.82, 0.14, 0.1}
  end
  local fix = lp.newFixture(body, shape, dens)
  fix:setFriction(0.6)
  fix:setRestitution(rest)
  fix:setUserData(obj)
  body:setUserData(obj)
  body:setAngularDamping(0.4)
  objects[#objects + 1] = obj
  while #objects > 60 do removeObject(objects[1]) end
  return obj
end

local function createBullet(x, y, ang, w)
  local body = lp.newBody(world, x, y, "dynamic")
  body:setBullet(true)
  body:setGravityScale(0)
  local rocket = (w.kind == "rocket")
  local shape = lp.newCircleShape(rocket and 5 or 3)
  local fix = lp.newFixture(body, shape, w.dens)
  fix:setGroupIndex(-1000)
  fix:setRestitution(0)
  body:setLinearVelocity(math.cos(ang) * w.speed, math.sin(ang) * w.speed)
  local b = { type = "bullet", body = body, kind = w.kind, dmg = w.dmg, life = 1.6, dead = false }
  fix:setUserData(b)
  body:setUserData(b)
  bullets[#bullets + 1] = b
  return b
end

local function buildWorld()
  lp.setMeter(METER)
  world = lp.newWorld(0, 9.81 * METER, true)
  local g = lp.newBody(world, 0, 0, "static")
  local function edge(x1, y1, x2, y2)
    local f = lp.newFixture(g, lp.newEdgeShape(x1, y1, x2, y2))
    f:setFriction(0.8)
    f:setUserData({ type = "ground" })
  end
  edge(0, GY, W, GY)
  edge(0, -600, 0, GY)
  edge(W, -600, W, GY)
  edge(0, -600, W, -600)
end

---------------------------------------------------------------- damage / explosions
local function breakPart(part)
  part.dead = true
  local rag = part.rag
  local x, y = part.body:getPosition()
  sprayJuice(x, y, 0, 0, 18, rag.pal, 340)
  spawnChunks(x, y, 0, 0, 6, rag.pal)
  shake = math.max(shake, 5)
  if part.kind == "torso" then
    rag.dead = true
    for _, p in ipairs(rag.parts) do
      if p.joint and not p.joint:isDestroyed() then p.joint:destroy() end
      p.joint = nil
    end
    sprayJuice(x, y, 0, 0, 20, rag.pal, 420)
  else
    if part.joint and not part.joint:isDestroyed() then part.joint:destroy() end
    part.joint = nil
    if part.kind == "head" then rag.dead = true end
  end
  play("pop")
end

local function applyDamage(part, amount, x, y, dx, dy)
  if part.gone or part.body:isDestroyed() then return end
  amount = math.min(amount, 80)
  if amount < 1 then return end
  local pal = part.rag.pal
  part.hp = part.hp - amount
  sprayJuice(x, y, dx, dy, math.min(24, 3 + math.floor(amount / 3)), pal, 260)
  if amount > 8 then spawnChunks(x, y, dx, dy, math.min(6, math.floor(amount / 10) + 1), pal) end
  play("splat")
  if part.hp <= 0 and not part.dead then breakPart(part) end
end

local function queueBarrel(obj)
  if obj.pending or obj.removed then return end
  obj.pending = true
  local x, y = obj.body:getPosition()
  expQ[#expQ + 1] = { x = x, y = y, R = 190, t = 0.05, obj = obj }
end

local function explode(x, y, R)
  shake = math.max(shake, 16)
  play("boom")
  fxs[#fxs + 1] = { x = x, y = y, t = 0, R = R }
  for _ = 1, 26 do
    local a, s = rnd(0, math.pi * 2), rnd(150, 600)
    addPt({ kind = "spark", x = x, y = y, vx = math.cos(a) * s, vy = math.sin(a) * s,
            life = rnd(0.2, 0.7), size = rnd(1.5, 3) })
  end
  for _ = 1, 10 do
    local a, s = rnd(0, math.pi * 2), rnd(20, 120)
    addPt({ kind = "smoke", x = x + rnd(-15, 15), y = y + rnd(-15, 15),
            vx = math.cos(a) * s, vy = math.sin(a) * s - 40, life = rnd(0.8, 1.6), size = rnd(14, 28) })
  end
  for _, body in ipairs(world:getBodies()) do
    if not body:isDestroyed() and body:getType() == "dynamic" then
      local ud = body:getUserData()
      if ud and ud.type ~= "bullet" then
        local bx, by = body:getWorldCenter()
        local dx, dy = bx - x, by - y
        local d = math.sqrt(dx * dx + dy * dy)
        if d < R then
          local f = 1 - d / R
          if d < 1 then dx, dy, d = 0, -1, 1 end
          local m = body:getMass()
          body:applyLinearImpulse(dx / d * m * 1000 * f, dy / d * m * 1000 * f - m * 250 * f)
          body:applyAngularImpulse(rnd(-1, 1) * m * 40 * f)
          if ud.type == "part" then
            applyDamage(ud, 100 * f, bx, by, dx / d, dy / d)
          elseif ud.type == "obj" and ud.kind == "barrel" and not ud.pending then
            ud.pending = true
            expQ[#expQ + 1] = { x = bx, y = by, R = 190, t = 0.12, obj = ud }
          end
        end
      end
    end
  end
end

---------------------------------------------------------------- tools
local function bodyAt(x, y)
  local exact, near, nd = nil, nil, 1e9
  world:queryBoundingBox(x - 22, y - 22, x + 22, y + 22, function(f)
    local b = f:getBody()
    if b:getType() == "dynamic" then
      local ud = f:getUserData()
      if ud and ud.type ~= "bullet" then
        if f:testPoint(x, y) then exact = f; return false end
        local bx, by = b:getPosition()
        local d = math.sqrt((bx - x) ^ 2 + (by - y) ^ 2)
        if d < nd then nd, near = d, f end
      end
    end
    return true
  end)
  return exact or near
end

local function deleteAt(x, y)
  local f = bodyAt(x, y)
  if not f then return end
  local ud = f:getUserData()
  addPt({ kind = "smoke", x = x, y = y, vx = 0, vy = -30, life = 0.6, size = 16 })
  play("del")
  if ud.type == "part" then removeRagdoll(ud.rag)
  elseif ud.type == "obj" then removeObject(ud) end
end

local function fire(tx, ty)
  local w = WEAPONS[wi]
  local left = tx < W / 2
  local sx, sy = left and 34 or (W - 34), GY - 34
  local ang = math.atan2(ty - sy, tx - sx)
  turret[left and "left" or "right"] = ang
  for _ = 1, w.pellets do
    local a = ang + rnd(-w.spread, w.spread)
    createBullet(sx + math.cos(a) * 30, sy + math.sin(a) * 30, a, w)
  end
  addPt({ kind = "spark", x = sx + math.cos(ang) * 34, y = sy + math.sin(ang) * 34,
          vx = math.cos(ang) * 200, vy = math.sin(ang) * 200, life = 0.08, size = 4 })
  play(w.kind == "rocket" and "rocket" or "shoot")
  shake = math.max(shake, 2)
end

local function spawn(kind, x, y)
  x = math.max(40, math.min(W - 40, x))
  y = math.max(60, math.min(GY - 80, y))
  if kind == "melon" then createMelon(x, y) else createProp(kind, x, y) end
  play("spawn")
end

local function clearAll()
  for i = #ragdolls, 1, -1 do removeRagdoll(ragdolls[i]) end
  for i = #objects, 1, -1 do removeObject(objects[i]) end
  for i = #bullets, 1, -1 do
    if not bullets[i].body:isDestroyed() then bullets[i].body:destroy() end
    bullets[i] = nil
  end
  pts, fxs, dmgQ, expQ = {}, {}, {}, {}
  for _, p in pairs(pointers) do p.mj = nil end
  stamp(function() lg.clear(0, 0, 0, 0) end)
  play("del")
end

local function setGrav()
  world:setGravity(0, 9.81 * METER * GRAVS[gravMode][2])
  for _, b in ipairs(world:getBodies()) do b:setAwake(true) end
end

local function buttonPress(x, y)
  for i, b in ipairs(BUTTONS) do
    if inRect(x, y, btnRect(i)) then
      if b.tool then
        if b.id == "gun" and tool == "gun" then wi = wi % #WEAPONS + 1 end
        tool = b.id
        hintTime = love.timer.getTime()
      elseif b.id == "slow" then slow = not slow
      elseif b.id == "grav" then gravMode = gravMode % #GRAVS + 1; setGrav()
      elseif b.id == "clear" then clearAll() end
      return
    end
  end
end

---------------------------------------------------------------- pointers
local function pointerDown(id, sx, sy)
  local x, y = toV(sx, sy)
  if y >= TB_Y then buttonPress(x, y) return end
  local p = { x = x, y = y, tool = tool }
  pointers[id] = p
  if tool == "grab" then
    local f = bodyAt(x, y)
    if f then
      local body = f:getBody()
      local bx, by = body:getPosition()
      p.mj = lp.newMouseJoint(body, x, y)
      p.mj:setMaxForce(body:getMass() * 800)
      p.mj:setFrequency(6)
      p.mj:setDampingRatio(0.8)
      body:setAwake(true)
    end
  elseif tool == "gun" then
    p.firing = true
    p.fireT = 0
  elseif tool == "boom" then
    expQ[#expQ + 1] = { x = x, y = y, R = 170, t = 0 }
  elseif tool == "delete" then
    deleteAt(x, y)
  else
    spawn(tool, x, y)
  end
end

local function pointerMove(id, sx, sy)
  local p = pointers[id]
  if not p then return end
  p.x, p.y = toV(sx, sy)
  if p.mj and not p.mj:isDestroyed() then p.mj:setTarget(p.x, p.y) end
  if p.tool == "delete" then deleteAt(p.x, p.y) end
end

local function pointerUp(id)
  local p = pointers[id]
  if p and p.mj and not p.mj:isDestroyed() then p.mj:destroy() end
  pointers[id] = nil
end

function love.touchpressed(id, x, y) usedTouch = true; pointerDown(id, x, y) end
function love.touchmoved(id, x, y) pointerMove(id, x, y) end
function love.touchreleased(id) pointerUp(id) end
function love.mousepressed(x, y, b, istouch) if not istouch and b == 1 then pointerDown("m", x, y) end end
function love.mousemoved(x, y, dx, dy, istouch) if not istouch then pointerMove("m", x, y) end end
function love.mousereleased(x, y, b, istouch) if not istouch and b == 1 then pointerUp("m") end end

function love.keypressed(key)
  if key == "escape" then love.event.quit() end
  if key == "m" then muted = not muted end
  if key == "space" then slow = not slow end
end

---------------------------------------------------------------- collisions (queue only!)
local function onBegin(fa, fb, contact)
  local ua, ub = fa:getUserData(), fb:getUserData()
  if not ua or not ub then return end
  local ba, bb = fa:getBody(), fb:getBody()
  local cx, cy = contact:getPositions()
  if not cx then cx, cy = ba:getPosition() end

  local function bulletHit(bl, other)
    if bl.dead then return end
    bl.dead = true
    if other.type == "part" then
      local vx, vy = bl.body:getLinearVelocity()
      local l = math.sqrt(vx * vx + vy * vy)
      if l < 1 then l = 1 end
      dmgQ[#dmgQ + 1] = { part = other, amount = bl.dmg, x = cx, y = cy, dx = vx / l, dy = vy / l }
    elseif other.type == "obj" and other.kind == "barrel" then
      queueBarrel(other)
    end
    if bl.kind == "rocket" then expQ[#expQ + 1] = { x = cx, y = cy, R = 150, t = 0 } end
  end
  if ua.type == "bullet" then bulletHit(ua, ub) return end
  if ub.type == "bullet" then bulletHit(ub, ua) return end

  local nx, ny = contact:getNormal()
  local vax, vay = ba:getLinearVelocity()
  local vbx, vby = bb:getLinearVelocity()
  local vn = math.abs((vax - vbx) * nx + (vay - vby) * ny)
  local ma = (ba:getType() == "dynamic") and ba:getMass() or 0
  local mb = (bb:getType() == "dynamic") and bb:getMass() or 0
  local m
  if ma == 0 then m = mb elseif mb == 0 then m = ma else m = ma * mb / (ma + mb) end
  local imp = m * vn / METER
  if imp < 0.7 then return end
  for _, u in ipairs({ ua, ub }) do
    if u.type == "part" then
      dmgQ[#dmgQ + 1] = { part = u, amount = (imp - 0.7) * 16, x = cx, y = cy, dx = -nx, dy = -ny }
    elseif u.type == "obj" and u.kind == "barrel" and imp > 3 then
      queueBarrel(u)
    end
  end
end

---------------------------------------------------------------- love callbacks
function love.load()
  math.randomseed(os.time())
  lg.setBackgroundColor(0.05, 0.05, 0.06)
  fontS = lg.newFont(14)
  fontM = lg.newFont(18)
  lg.setFont(fontM)
  updateScale()
  pcall(initSounds)
  buildWorld()
  world:setCallbacks(onBegin)
  juiceCanvas = lg.newCanvas(W, H)

  bgCanvas = lg.newCanvas(W, H)
  lg.push("all")
  lg.origin()
  lg.setCanvas(bgCanvas)
  lg.clear(0.74, 0.79, 0.83, 1)
  lg.setColor(0.68, 0.73, 0.78)
  for x = 0, W, 80 do lg.rectangle("fill", x, 0, 2, GY) end
  for y = 0, GY, 80 do lg.rectangle("fill", 0, y, W, 2) end
  lg.setColor(0.32, 0.34, 0.38)
  lg.rectangle("fill", 0, GY, W, TB_Y - GY + 10)
  lg.setColor(0.45, 0.47, 0.52)
  lg.rectangle("fill", 0, GY, W, 4)
  lg.pop()

  hintTime = love.timer.getTime()
  createMelon(300, 300)
  createMelon(480, 250)
  createProp("crate", 700, 300)
end

function love.resize() updateScale() end

local function processQueues(dt)
  for i = 1, #dmgQ do
    local e = dmgQ[i]
    applyDamage(e.part, e.amount, e.x, e.y, e.dx, e.dy)
  end
  dmgQ = {}
  local rest = {}
  for _, e in ipairs(expQ) do
    e.t = e.t - dt
    if e.t <= 0 then
      if e.obj then
        if not e.obj.removed then
          local bx, by = e.obj.body:getPosition()
          e.x, e.y = bx, by
          removeObject(e.obj)
          explode(e.x, e.y, e.R)
        end
      else
        explode(e.x, e.y, e.R)
      end
    else
      rest[#rest + 1] = e
    end
  end
  expQ = rest
end

function love.update(dt)
  dt = math.min(dt, 1 / 30)
  local sdt = dt * (slow and 0.25 or 1)
  shake = math.max(0, shake - dt * 30)

  for _, p in pairs(pointers) do
    if p.firing then
      p.fireT = p.fireT - dt
      if p.fireT <= 0 then
        fire(p.x, p.y)
        p.fireT = WEAPONS[wi].delay
      end
    end
  end

  acc = acc + sdt
  local steps = 0
  while acc >= STEP and steps < 6 do
    world:update(STEP)
    acc = acc - STEP
    steps = steps + 1
  end
  if steps >= 6 then acc = 0 end

  processQueues(sdt)

  -- bullets
  for i = #bullets, 1, -1 do
    local b = bullets[i]
    b.life = b.life - sdt
    local out = false
    if not b.body:isDestroyed() then
      local x, y = b.body:getPosition()
      out = x < -20 or x > W + 20 or y < -700 or y > H
      if b.kind == "rocket" and not b.dead then
        addPt({ kind = "smoke", x = x, y = y, vx = rnd(-20, 20), vy = rnd(-20, 20), life = 0.5, size = 8 })
      end
    end
    if b.dead or b.life <= 0 or out then
      if not b.body:isDestroyed() then b.body:destroy() end
      table.remove(bullets, i)
    end
  end

  -- fx rings
  for i = #fxs, 1, -1 do
    fxs[i].t = fxs[i].t + sdt
    if fxs[i].t > 0.4 then table.remove(fxs, i) end
  end

  -- particles
  for i = #pts, 1, -1 do
    local q = pts[i]
    q.life = q.life - sdt
    q.x, q.y = q.x + q.vx * sdt, q.y + q.vy * sdt
    local remove = q.life <= 0
    if q.kind == "juice" or q.kind == "chunk" or q.kind == "seed" then
      q.vy = q.vy + 800 * sdt
      if q.rot then q.rot = q.rot + q.vr * sdt end
      if q.y >= GY - 1 or q.x < 0 or q.x > W then
        remove = true
        local landX, landY = math.max(0, math.min(W, q.x)), math.min(q.y, GY)
        stamp(function()
          if q.kind == "juice" then
            lg.setColor(q.col[1], q.col[2], q.col[3], 0.75)
            lg.ellipse("fill", landX, landY, q.size * 1.8, q.size * 0.7)
          elseif q.kind == "chunk" then
            lg.setColor(q.col[1], q.col[2], q.col[3], 0.95)
            lg.ellipse("fill", landX, landY - 2, q.size * 1.2, q.size * 0.6)
          else
            lg.setColor(0.05, 0.05, 0.05, 0.9)
            lg.ellipse("fill", landX, landY - 1, 2, 1)
          end
        end)
      end
    elseif q.kind == "spark" then
      q.vy = q.vy + 300 * sdt
    elseif q.kind == "smoke" then
      q.vx, q.vy = q.vx * (1 - 2 * sdt), q.vy * (1 - 2 * sdt) - 20 * sdt
      q.size = q.size + 20 * sdt
    end
    if remove then table.remove(pts, i) end
  end
end

---------------------------------------------------------------- drawing
local function drawPart(part)
  local b = part.body
  if b:isDestroyed() then return end
  local pal = part.rag.pal
  local x, y = b:getPosition()
  local dmg = math.max(0, math.min(1, 1 - part.hp / part.maxhp))
  lg.push()
  lg.translate(x, y)
  lg.rotate(b:getAngle())
  lg.setLineWidth(2)
  if part.r then
    local r = part.r
    lg.setColor(pal.rind); lg.circle("fill", 0, 0, r)
    lg.setColor(pal.stripe)
    for _, sx in ipairs({ -8, 0, 8 }) do
      local h = math.sqrt(r * r - sx * sx)
      lg.line(sx, -h + 1, sx, h - 1)
    end
    if dmg > 0.05 then
      lg.setColor(pal.flesh[1], pal.flesh[2], pal.flesh[3], math.min(1, dmg * 1.5))
      lg.circle("fill", 3, 3, r * 0.6 * math.min(1, dmg * 1.4))
      lg.setColor(0.05, 0.05, 0.05)
      lg.circle("fill", 2, 4, 1.4); lg.circle("fill", 6, 2, 1.4)
    end
    -- face
    if part.rag.dead then
      lg.setColor(0.1, 0.1, 0.1)
      for _, ex in ipairs({ -6, 6 }) do
        lg.line(ex - 3, -5, ex + 3, 1); lg.line(ex - 3, 1, ex + 3, -5)
      end
      lg.arc("line", "open", 0, 11, 5, math.pi + 0.3, 2 * math.pi - 0.3)
    else
      lg.setColor(1, 1, 1)
      lg.circle("fill", -6, -2, 4.5); lg.circle("fill", 6, -2, 4.5)
      lg.setColor(0.05, 0.05, 0.05)
      lg.circle("fill", -5, -1, 2); lg.circle("fill", 7, -1, 2)
      if part.hp < part.maxhp * 0.6 then
        lg.arc("line", "open", 0, 11, 5, math.pi + 0.3, 2 * math.pi - 0.3)
      else
        lg.arc("line", "open", 0, 4, 6, 0.3, math.pi - 0.3)
      end
    end
  else
    local w, h = part.w, part.h
    lg.setColor(pal.rind); lg.rectangle("fill", -w / 2, -h / 2, w, h, 4, 4)
    lg.setColor(pal.stripe)
    lg.line(-w * 0.22, -h / 2 + 3, -w * 0.22, h / 2 - 3)
    lg.line(w * 0.22, -h / 2 + 3, w * 0.22, h / 2 - 3)
    if dmg > 0.05 then
      lg.setColor(pal.flesh[1], pal.flesh[2], pal.flesh[3], math.min(1, dmg * 1.5))
      lg.rectangle("fill", -w * 0.3, -h * 0.2, w * 0.6, h * 0.45 * math.min(1, dmg * 1.4), 3, 3)
    end
    if part.dead then
      lg.setColor(pal.flesh)
      lg.rectangle("fill", -w / 2, -h / 2, w, 6, 2, 2)
      lg.setColor(0.05, 0.05, 0.05)
      lg.circle("fill", -w * 0.2, -h / 2 + 3, 1.2); lg.circle("fill", w * 0.2, -h / 2 + 3, 1.2)
    end
  end
  lg.pop()
end

local function drawObj(o)
  local b = o.body
  if b:isDestroyed() then return end
  local x, y = b:getPosition()
  lg.push()
  lg.translate(x, y)
  lg.rotate(b:getAngle())
  lg.setLineWidth(2)
  if o.kind == "crate" then
    lg.setColor(o.col); lg.rectangle("fill", -o.w / 2, -o.h / 2, o.w, o.h)
    lg.setColor(o.col[1] * 0.6, o.col[2] * 0.6, o.col[3] * 0.6)
    lg.rectangle("line", -o.w / 2, -o.h / 2, o.w, o.h)
    lg.line(-o.w / 2, -o.h / 2, o.w / 2, o.h / 2); lg.line(-o.w / 2, o.h / 2, o.w / 2, -o.h / 2)
  elseif o.kind == "plank" then
    lg.setColor(o.col); lg.rectangle("fill", -o.w / 2, -o.h / 2, o.w, o.h, 2, 2)
    lg.setColor(0.55, 0.42, 0.24)
    lg.line(-o.w / 2 + 6, 0, o.w / 2 - 6, 0)
  elseif o.kind == "ball" then
    lg.setColor(o.col); lg.circle("fill", 0, 0, o.r)
    lg.setColor(1, 1, 1, 0.8); lg.arc("line", "open", 0, 0, o.r * 0.6, 3.5, 4.8)
    lg.setColor(0, 0, 0, 0.35); lg.line(-o.r, 0, o.r, 0)
  elseif o.kind == "barrel" then
    lg.setColor(o.col); lg.rectangle("fill", -o.w / 2, -o.h / 2, o.w, o.h, 5, 5)
    lg.setColor(0.2, 0.05, 0.05)
    lg.rectangle("fill", -o.w / 2, -o.h / 2 + 8, o.w, 4)
    lg.rectangle("fill", -o.w / 2, o.h / 2 - 12, o.w, 4)
    lg.setColor(1, 0.85, 0.1)
    lg.polygon("fill", 0, -8, 8, 8, -8, 8)
    lg.setColor(0.1, 0.1, 0.1); lg.rectangle("fill", -1, -2, 2, 6)
  end
  lg.pop()
end

local function drawTurret(side, bx)
  local ang = turret[side]
  lg.push()
  lg.translate(bx, GY - 34)
  lg.setColor(0.25, 0.27, 0.3); lg.circle("fill", 0, 0, 16)
  lg.rotate(ang)
  lg.setColor(0.15, 0.15, 0.17); lg.rectangle("fill", 0, -5, 32, 10, 2, 2)
  lg.pop()
end

local function drawButton(i, b)
  local x, y, w, h = btnRect(i)
  local active = (b.tool and tool == b.id) or (b.id == "slow" and slow) or (b.id == "grav" and gravMode > 1)
  if active then lg.setColor(0.2, 0.55, 0.3) else lg.setColor(0.18, 0.2, 0.24) end
  lg.rectangle("fill", x, y, w, h, 8, 8)
  lg.setColor(active and 0.6 or 0.4, active and 1 or 0.42, active and 0.7 or 0.46)
  lg.setLineWidth(2)
  lg.rectangle("line", x, y, w, h, 8, 8)
  lg.setColor(1, 1, 1)
  local label = b.label
  if b.id == "gun" then label = "GUN: " .. WEAPONS[wi].name
  elseif b.id == "grav" then label = "GRAV: " .. GRAVS[gravMode][1]
  elseif b.id == "slow" then label = slow and "SLOW-MO: ON" or "SLOW-MO" end
  lg.printf(label, x, y + h / 2 - 10, w, "center")
end

function love.draw()
  lg.setFont(fontM)
  lg.push()
  lg.translate(offx, offy)
  lg.scale(scale)
  lg.setScissor(offx, offy, W * scale, H * scale)

  lg.push()
  if shake > 0 then lg.translate(rnd(-shake, shake), rnd(-shake, shake)) end
  lg.setColor(1, 1, 1)
  lg.draw(bgCanvas, 0, 0)
  lg.draw(juiceCanvas, 0, 0)
  drawTurret("left", 34)
  drawTurret("right", W - 34)

  for _, o in ipairs(objects) do drawObj(o) end
  for _, r in ipairs(ragdolls) do
    for _, p in ipairs(r.parts) do drawPart(p) end
  end

  lg.setLineWidth(2)
  for _, b in ipairs(bullets) do
    if not b.body:isDestroyed() then
      local x, y = b.body:getPosition()
      local vx, vy = b.body:getLinearVelocity()
      if b.kind == "rocket" then
        lg.setColor(0.6, 0.6, 0.65); lg.circle("fill", x, y, 5)
        lg.setColor(1, 0.6, 0.1); lg.circle("fill", x - vx * 0.01, y - vy * 0.01, 4)
      else
        lg.setColor(1, 0.9, 0.5)
        lg.line(x, y, x - vx * 0.02, y - vy * 0.02)
      end
    end
  end

  for _, q in ipairs(pts) do
    if q.kind == "juice" then
      lg.setColor(q.col[1], q.col[2], q.col[3]); lg.circle("fill", q.x, q.y, q.size)
    elseif q.kind == "chunk" then
      lg.push(); lg.translate(q.x, q.y); lg.rotate(q.rot)
      lg.setColor(q.col); lg.rectangle("fill", -q.size / 2, -q.size / 2, q.size, q.size * 0.7)
      lg.pop()
    elseif q.kind == "seed" then
      lg.setColor(q.col); lg.circle("fill", q.x, q.y, q.size)
    elseif q.kind == "spark" then
      lg.setColor(1, 0.8, 0.3, math.min(1, q.life * 3)); lg.circle("fill", q.x, q.y, q.size)
    elseif q.kind == "smoke" then
      lg.setColor(0.25, 0.25, 0.27, math.max(0, math.min(0.6, q.life * 0.6)))
      lg.circle("fill", q.x, q.y, q.size)
    end
  end
  for _, f in ipairs(fxs) do
    local k = f.t / 0.4
    lg.setColor(1, 0.8, 0.3, (1 - k) * 0.9)
    lg.circle("fill", f.x, f.y, f.R * 0.4 * (1 - k * 0.5))
    lg.setLineWidth(6 * (1 - k))
    lg.setColor(1, 0.5, 0.1, (1 - k))
    lg.circle("line", f.x, f.y, f.R * k)
  end
  lg.pop()

  -- HUD
  lg.setFont(fontS)
  lg.setColor(0, 0, 0, 0.45)
  lg.rectangle("fill", 8, 8, 470, 26, 6, 6)
  lg.setColor(1, 1, 1)
  lg.print((HINTS[tool] or ""), 16, 13)
  lg.setColor(0, 0, 0, 0.45)
  lg.rectangle("fill", W - 200, 8, 192, 26, 6, 6)
  lg.setColor(1, 1, 1)
  lg.printf("Melons " .. #ragdolls .. "   Props " .. #objects, W - 200, 13, 192, "center")
  lg.setFont(fontM)

  -- toolbar
  lg.setColor(0.09, 0.1, 0.12)
  lg.rectangle("fill", 0, TB_Y, W, H - TB_Y)
  for i, b in ipairs(BUTTONS) do drawButton(i, b) end

  lg.setScissor()
  lg.pop()
end
