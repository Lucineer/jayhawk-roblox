-- Jayhawk Rescue — Client: arcade helicopter flight controller + HUD
-- Scripted arcade flight (lerped velocity), NOT true physics.
-- Controls: WASD move, R/F or Space/Shift altitude, Q/E yaw. Touch: on-screen buttons.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- Tuning (studs / seconds)
local MAX_SPEED = 120 -- horizontal top speed
local MAX_CLIMB = 60 -- vertical speed
local ACCEL_LERP = 4 -- how fast velocity converges (higher = snappier)
local TURN_SPEED = math.rad(120) -- yaw degrees per second
local HOVER_HEIGHT = 30 -- spawn hover altitude above helipad

-- Input state
local input = {
	forward = 0, -- W/S or up/down
	strafe = 0, -- A/D
	up = 0, -- R/Space
	down = 0, -- F/Shift
	yawLeft = 0, -- Q
	yawRight = 0, -- E
}

local KEYMAP = {
	[Enum.KeyCode.W] = "forward",
	[Enum.KeyCode.Up] = "forward",
	[Enum.KeyCode.S] = "forwardNeg",
	[Enum.KeyCode.Down] = "forwardNeg",
	[Enum.KeyCode.A] = "strafeNeg",
	[Enum.KeyCode.Left] = "strafeNeg",
	[Enum.KeyCode.D] = "strafe",
	[Enum.KeyCode.Right] = "strafe",
	[Enum.KeyCode.R] = "up",
	[Enum.KeyCode.Space] = "up",
	[Enum.KeyCode.F] = "down",
	[Enum.KeyCode.LeftShift] = "down",
	[Enum.KeyCode.Q] = "yawLeft",
	[Enum.KeyCode.E] = "yawRight",
}

local function setInput(keyName, value)
	if keyName == "forwardNeg" then
		input.forward = -value
	elseif keyName == "strafeNeg" then
		input.strafe = -value
	else
		input[keyName] = value
	end
end

UserInputService.InputBegan:Connect(function(io, gpe)
	if gpe then
		return
	end
	local k = KEYMAP[io.KeyCode]
	if k then
		setInput(k, 1)
	end
end)

UserInputService.InputEnded:Connect(function(io)
	local k = KEYMAP[io.KeyCode]
	if k then
		setInput(k, 0)
	end
end)

-- Helicopter rig
local heli = nil
local heliRoot = nil -- PrimaryPart (Body)
local rotor = nil
local velocity = Vector3.zero
local yaw = 0

local function findHeli()
	heli = workspace:WaitForChild("Jayhawk", 10)
	if not heli then
		warn("[Jayhawk] No Jayhawk model in Workspace")
		return false
	end
	heliRoot = heli:WaitForChild("Body", 10)
	if not heliRoot then
		warn("[Jayhawk] Jayhawk has no Body part")
		return false
	end
	heli.PrimaryPart = heliRoot
	rotor = heli:FindFirstChild("Rotor", true)
	return true
end

-- Network ownership for responsive handling (driver owns physics)
local function claimNetworkOwnership()
	if heliRoot then
		pcall(function()
			heliRoot:SetNetworkOwner(player)
		end)
	end
end

-- Flight step: arcade velocity lerp
local function stepFlight(dt)
	if not heliRoot then
		return
	end

	-- Yaw
	yaw += (input.yawRight - input.yawLeft) * TURN_SPEED * dt

	-- Desired horizontal velocity in heli-local space, rotated by yaw
	local fwd = input.forward
	local str = input.strafe
	local wishDir = Vector3.new(str, 0, -fwd) -- -Z is forward
	local cosY, sinY = math.cos(yaw), math.sin(yaw)
	local worldDir = Vector3.new(
		wishDir.X * cosY - wishDir.Z * sinY,
		0,
		wishDir.X * sinY + wishDir.Z * cosY
	)
	local targetVel = worldDir * MAX_SPEED
	targetVel = Vector3.new(targetVel.X, (input.up - input.down) * MAX_CLIMB, targetVel.Z)

	-- Lerp toward target (arcade feel, matches web version)
	local t = math.min(1, dt * ACCEL_LERP)
	velocity = velocity:Lerp(targetVel, t)

	-- Move the model (CFrame, not physics — stable and predictable)
	local pos = heliRoot.Position + velocity * dt
	-- Keep above water
	if pos.Y < 8 then
		pos = Vector3.new(pos.X, 8, pos.Z)
		velocity = Vector3.new(velocity.X, math.max(0, velocity.Y), velocity.Z)
	end

	-- Tilt into motion for game feel (matches web heli.rotateX/rotateZ)
	local hSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local tiltAmt = math.clamp(hSpeed / MAX_SPEED, 0, 1) * 0.35
	-- Tilt forward along local velocity direction
	local localVel = heliRoot.CFrame:VectorToObjectSpace(velocity)
	local pitch = math.clamp(-localVel.Z / MAX_SPEED, -1, 1) * 0.35
	local roll = math.clamp(-localVel.X / MAX_SPEED, -1, 1) * 0.35

	heli:PivotTo(CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll))

	-- Spin rotor (cosmetic)
	if rotor then
		rotor.CFrame = rotor.CFrame * CFrame.Angles(0, dt * 30, 0)
	end

	-- Chase camera is default; update HUD readouts
	updateHUD(pos, hSpeed)
end

-- HUD
local hud = nil
local rescueBar = nil
local distressLabel = nil
local scoreLabel = nil

local function buildHUD()
	local gui = player:WaitForChild("PlayerGui")
	hud = gui:WaitForChild("JayhawkHUD", 10)
	if hud then
		rescueBar = hud:FindFirstChild("RescueBar", true)
		distressLabel = hud:FindFirstChild("DistressLabel", true)
		scoreLabel = hud:FindFirstChild("ScoreLabel", true)
	end
end

local lastDistress = ""

function updateHUD(pos, hSpeed)
	-- Lightweight: update every frame is fine for text
	if scoreLabel then
		-- score text set by ScoreUpdate event; nothing per-frame needed
	end
end

-- RemoteEvent handlers
local function onDistress(name, problem, x, z)
	lastDistress = string.format("%s — %s", name, problem)
	if distressLabel then
		distressLabel.Text = "🆘 " .. lastDistress
		distressLabel.Visible = true
	end
	print("[Jayhawk] Distress: " .. lastDistress)
end

local function onRescueProgress(frac, inZone)
	if rescueBar then
		rescueBar.Visible = inZone
		local fill = rescueBar:FindFirstChild("Fill", true)
		if fill and fill:IsA("Frame") then
			fill.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)
		end
	end
	if distressLabel and not inZone and lastDistress ~= "" then
		-- keep showing distress info while active
	end
end

local function onRescueComplete(name, pts, rescuesCount, totalScore)
	if distressLabel then
		distressLabel.Text = string.format("✅ RESCUED %s +%d pts!", name, pts)
	end
	if rescueBar then
		rescueBar.Visible = false
	end
	task.delay(3, function()
		if distressLabel then
			distressLabel.Visible = false
		end
		lastDistress = ""
	end)
end

local function onScoreUpdate(rescuesCount, totalScore)
	if scoreLabel then
		scoreLabel.Text = string.format("RESCUES %d   SCORE %d", rescuesCount, totalScore)
	end
end

local function bindRemotes()
	local function waitRemote(name)
		return ReplicatedStorage:WaitForChild(name, 10)
	end
	local d = waitRemote("DistressCall")
	if d then
		d.OnClientEvent:Connect(onDistress)
	end
	local p = waitRemote("RescueProgress")
	if p then
		p.OnClientEvent:Connect(onRescueProgress)
	end
	local c = waitRemote("RescueComplete")
	if c then
		c.OnClientEvent:Connect(onRescueComplete)
	end
	local s = waitRemote("ScoreUpdate")
	if s then
		s.OnClientEvent:Connect(onScoreUpdate)
	end
end

-- Boot
if findHeli() then
	claimNetworkOwnership()
	buildHUD()
	bindRemotes()
	RunService.Heartbeat:Connect(stepFlight)
	print("[Jayhawk] Client flight controller running")
else
	warn("[Jayhawk] Client could not find helicopter")
end
