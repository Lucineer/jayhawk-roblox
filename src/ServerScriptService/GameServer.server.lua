-- Jayhawk Rescue — Server game logic
-- Distress spawner, rescue validation, scoring.
-- Translated from helicopter/js/heli-game.js (web version).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Scale: 1 stud ≈ 0.28 m (from web version meters)
local RESCUE_RADIUS = 100 -- studs (~30 m)
local RESCUE_ALT_MIN = 15 -- studs above water (~4 m)
local RESCUE_ALT_MAX = 90 -- studs above water (~26 m)
local RESCUE_TIME = 8 -- seconds of hover
local WATER_Y = 0 -- water plane height in studs

local BOAT_NAMES = {
	"F/V Kittiwake",
	"M/V Sea Star",
	"F/V Northern Light",
	"S/V Windward",
	"M/V Halibut King",
	"F/V Storm Petrel",
}

local PROBLEMS = {
	"FIRE ON BOARD",
	"TAKING ON WATER",
	"MEDICAL EMERGENCY",
	"ENGINE FAILURE",
	"LOST IN FOG",
}

-- RemoteEvents for client communication
local function getOrCreateRemote(name, className)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then
		return existing
	end
	local r = Instance.new(className or "RemoteEvent")
	r.Name = name
	r.Parent = ReplicatedStorage
	return r
end

local distressEvent = getOrCreateRemote("DistressCall") -- server -> client: boat info
local rescueProgress = getOrCreateRemote("RescueProgress") -- server -> client: 0..1 progress
local rescueDoneEvent = getOrCreateRemote("RescueComplete") -- server -> client: score info
local scoreEvent = getOrCreateRemote("ScoreUpdate") -- server -> client: rescues, score

-- Game state
local phase = "waiting" -- waiting | active | cooldown
local phaseT = 0
local boat = nil -- the distress boat Model
local boatData = nil -- {name, problem, spawnTime}
local rescueT = 0
local rescues = 0
local score = 0

local function pickRandom(t)
	return t[math.random(1, #t)]
end

local function getHeli()
	local heli = workspace:FindFirstChild("Jayhawk")
	if heli then
		return heli:FindFirstChild("PrimaryPart") or heli:FindFirstChild("Body")
	end
	return nil
end

local function spawnDistressBoat()
	-- Find a spawn point 500–2000 studs from base, on water
	local base = workspace:FindFirstChild("SitkaBase")
	local basePos = base and base:GetPivot().Position or Vector3.new(0, 0, 0)

	local angle = math.random() * math.pi * 2
	local dist = 500 + math.random() * 1500
	local x = basePos.X + math.cos(angle) * dist
	local z = basePos.Z + math.sin(angle) * dist

	local template = workspace:FindFirstChild("FishingBoatTemplate")
	if not template then
		warn("[Jayhawk] No FishingBoatTemplate in Workspace")
		return
	end

	boat = template:Clone()
	boat.Name = "DistressBoat"
	boat:PivotTo(CFrame.new(x, WATER_Y, z))
	boat.Parent = workspace

	boatData = {
		name = pickRandom(BOAT_NAMES),
		problem = pickRandom(PROBLEMS),
		spawnTime = os.clock(),
		pos = Vector3.new(x, WATER_Y, z),
	}

	-- Flash the distress beacon
	local beacon = boat:FindFirstChild("DistressBeacon", true)
	if beacon and beacon:IsA("PointLight") then
		task.spawn(function()
			while boat and boat.Parent do
				beacon.Enabled = not beacon.Enabled
				task.wait(0.5)
			end
		end)
	end

	phase = "active"
	rescueT = 0

	distressEvent:FireAllClients(boatData.name, boatData.problem, x, z)
	print(string.format("[Jayhawk] DISTRESS: %s — %s (%.0f studs out)", boatData.name, boatData.problem, dist))
end

local function clearBoat()
	if boat then
		boat:Destroy()
		boat = nil
	end
	boatData = nil
	rescueT = 0
end

local function completeRescue()
	local elapsed = os.clock() - boatData.spawnTime
	local speedBonus = math.max(0, 200 - math.floor(elapsed))
	local pts = 100 + speedBonus
	rescues += 1
	score += pts

	rescueDoneEvent:FireAllClients(boatData.name, pts, rescues, score)
	scoreEvent:FireAllClients(rescues, score)
	print(string.format("[Jayhawk] RESCUED %s +%d pts (total %d)", boatData.name, pts, score))

	clearBoat()
	phase = "cooldown"
	phaseT = 0
end

-- Main loop: Heartbeat for rescue zone check
game:GetService("RunService").Heartbeat:Connect(function(dt)
	if phase == "waiting" then
		phaseT += dt
		if phaseT > 5 then
			phaseT = 0
			spawnDistressBoat()
		end
	elseif phase == "cooldown" then
		phaseT += dt
		if phaseT > 5 then
			phaseT = 0
			phase = "waiting"
		end
	elseif phase == "active" and boat and boatData then
		local heliRoot = getHeli()
		if not heliRoot then
			return
		end

		local heliPos = heliRoot.Position
		local dx = boatData.pos.X - heliPos.X
		local dz = boatData.pos.Z - heliPos.Z
		local hd = math.sqrt(dx * dx + dz * dz)
		local alt = heliPos.Y - WATER_Y

		local inZone = hd < RESCUE_RADIUS and alt > RESCUE_ALT_MIN and alt < RESCUE_ALT_MAX

		if inZone then
			rescueT += dt
			rescueProgress:FireAllClients(rescueT / RESCUE_TIME, true)
			if rescueT >= RESCUE_TIME then
				completeRescue()
			end
		else
			if rescueT > 0 then
				rescueT = 0
				rescueProgress:FireAllClients(0, false)
			end
		end
	end
end)

-- Reset on player join (single-player prototype: just start the loop)
game:GetService("Players").PlayerAdded:Connect(function(player)
	scoreEvent:FireClient(player, rescues, score)
end)

print("[Jayhawk] Server game logic loaded. Waiting for distress calls…")
