class('Freelook')

function Freelook:__init()

	self._freelookKey = InputDeviceKeys.IDK_LeftAlt

	self._twoPi = math.pi * 2
	self._halfPi = math.pi / 2

	self._rotationSpeed = 1.916686

	self._heightOffset = 0.12
	self._frontOffset = 0.05
	self._horizontalOffset = 0.05

	-- Limit camera by vertical axis
	self._minPitch = -50.0 * (math.pi / 180.0)
	self._maxPitch = 80.0 * (math.pi / 180.0)

	-- Limit camera by horizontal axi
	self._maxYawModifier = 1.25

	self._freeCamYaw = 0.0
	self._freeCamPitch = 0.0
	self._freeCamPos = nil

	self._lockYaw = false
	self._authoritativeYaw = 0.0

	self._useFreelook = false

	self._data = nil
	self._entity = nil
	
	self._gameRenderSettings = nil
	self._changedState = false

	Hooks:Install('Input:PreUpdate', 100, self, self._onInputPreUpdate)
	Events:Subscribe('Engine:Update', self, self._onUpdate)
	Events:Subscribe('Level:Destroy', self, self._onLevelDestroy)
	Events:Subscribe('Level:Loaded', self, self._onLevelLoaded)
end

function Freelook:enable()
	if self._entity ~= nil then
		return
	end

	-- Create data for freelook camera entity
	self._data = CameraEntityData()
	self._data.fov = self._gameRenderSettings.fovMultiplier * 55
	self._data.enabled = true
	self._data.priority = 99999
	self._data.nameId = 'freelook-cam'
	self._data.transform = LinearTransform()

	-- And then create the camera entity.
	self._entity = EntityManager:CreateEntity(self._data, self._data.transform)
	self._entity:Init(Realm.Realm_Client, true)
end

function Freelook:_takeControl(player)
	if self._entity ~= nil then
		self._useFreelook = true
		self._entity:FireEvent('TakeControl')

		if self._wentKeyDown then
			self:_showCrosshair(false)

			self._wentKeyDown = false
			self._data.fov = self._gameRenderSettings.fovMultiplier * 55

			player:EnableInput(EntryInputActionEnum.EIAYaw, false)
			player:EnableInput(EntryInputActionEnum.EIAPitch, false)
		end
	end
end

function Freelook:_releaseControl(player)
	self._useFreelook = false

	if self._entity ~= nil then
		self._entity:FireEvent('ReleaseControl')

		if self._wentKeyUp then
			self:_showCrosshair(true)
			self:_hideHead(false, player)

			self._wentKeyUp = false

			player:EnableInput(EntryInputActionEnum.EIAYaw, true)
			player:EnableInput(EntryInputActionEnum.EIAPitch, true)

			self._lockYaw = false
		end
	end
end

function Freelook:_showCrosshair(visible)
	local s_clientUIGraphEntityIterator = EntityManager:GetIterator("ClientUIGraphEntity")

	local s_clientUIGraphEntity = s_clientUIGraphEntityIterator:Next()
	while s_clientUIGraphEntity do
		if s_clientUIGraphEntity.data.instanceGuid == Guid('9F8D5FCA-9B2A-484F-A085-AFF309DC5B7A') then
			s_clientUIGraphEntity = Entity(s_clientUIGraphEntity)
			if visible then
				s_clientUIGraphEntity:FireEvent('ShowCrosshair')
			else
				s_clientUIGraphEntity:FireEvent('HideCrosshair')
			end
			return
		end
		s_clientUIGraphEntity = s_clientUIGraphEntityIterator:Next()
	end
end

function Freelook:_onLevelDestroy()
	local player = PlayerManager:GetLocalPlayer()
	self:_releaseControl(player)

	if self._entity == nil then
		return
	end

	-- Destroy the camera entity.
	self._entity:Destroy()
	self._data = nil
	self._entity = nil
	self._freeCamPos = nil
	self._useFreelook = nil
	self._gameRenderSettings = nil
	self._wentKeyDown = false
	self._wentKeyUp = false
end

function Freelook:_onLevelLoaded()
	self._gameRenderSettings = ResourceManager:GetSettings("GameRenderSettings")

	if self._gameRenderSettings ~= nil then
		self._gameRenderSettings = GameRenderSettings(self._gameRenderSettings)
	else
		-- Just in case if we dont get the settings
		self._gameRenderSettings = { fovMultiplier = 1.36 }
	end
end

function Freelook:_onInputPreUpdate(hook, cache, dt)
	local player = PlayerManager:GetLocalPlayer()

	if player == nil then
		return
	end

	if not player.alive then
		return
	end

	if player.inVehicle then
			if self._useFreelook then
				self:_releaseControl(player)
			end
		return
	end

	-- Check if the player is locking the camera.
	if self._freelookKey ~= InputDeviceKeys.IDK_None and InputManager:IsKeyDown(self._freelookKey) then
		if not self._useFreelook and player.input ~= nil then
			self._useFreelook = true

			self._freeCamYaw = player.input.authoritativeAimingYaw
			self._freeCamPitch = player.input.authoritativeAimingPitch
			
			self._wentKeyDown = true
		end
	elseif self._useFreelook and self._freelookKey ~= InputDeviceKeys.IDK_None and not InputManager:IsKeyDown(self._freelookKey) then
		self._useFreelook = false
		
		self._wentKeyUp = true
	end

	-- If we are locking then prevent the player from looking around.
	if self._useFreelook then
		if not self._lockYaw then
			self._authoritativeYaw = self._freeCamYaw
			self._lockYaw = true
		end
		self:_takeControl(player)
		self:_hideHead(true, player)
	elseif self._wentKeyUp then
		self:_releaseControl(player)
	end

	if self._useFreelook then

		-- Limit Pitch
		local rotatePitch = cache[InputConceptIdentifiers.ConceptPitch] * self._rotationSpeed
		self._freeCamPitch = self._freeCamPitch + rotatePitch
		if self._freeCamPitch > self._maxPitch then
			self._freeCamPitch = self._maxPitch
		end

		if self._freeCamPitch < self._minPitch then
			self._freeCamPitch = self._minPitch
		end

		-- Limit Yaw
		local rotateYaw = cache[InputConceptIdentifiers.ConceptYaw] * self._rotationSpeed
		self._freeCamYaw = self._freeCamYaw + rotateYaw

		local minYaw = self._authoritativeYaw - (self._maxYawModifier * self._halfPi)
		local maxYaw = self._authoritativeYaw + (self._maxYawModifier * self._halfPi)

		while self._freeCamYaw < minYaw do
			self._freeCamYaw = minYaw
		end

		while self._freeCamYaw > maxYaw do
			self._freeCamYaw = maxYaw
		end

	end
end

function Freelook:_hideHead(hide, player)
	if player == nil then
		return
	end

	if player.soldier == nil then
		return
	end

	local headScale = (hide and 0.0 or 1.0) 

	local transformQuat = player.soldier.ragdollComponent:GetLocalTransform(45)

	if transformQuat ~= nil then
		transformQuat.transAndScale.w = headScale
		player.soldier.ragdollComponent:SetLocalTransform(45, transformQuat)
	end
end

function Freelook:_onUpdate(delta, simDelta)
	-- Don't update if the camera is not active.
	if not self._useFreelook then
		return
	end

	-- Don't update if we don't have a player with an alive soldier.
	local player = PlayerManager:GetLocalPlayer()

	if player == nil or player.soldier == nil or player.input == nil then
		return
	end

	-- Fix angles so we're looking at the right thing.
	local yaw = self._freeCamYaw - math.pi / 2
	local pitch = self._freeCamPitch + math.pi / 2

	local playerHeadQuat = player.soldier.ragdollComponent:GetInterpolatedWorldTransform(46)

	if playerHeadQuat == nil then
		return
	end

	local headTransform = playerHeadQuat.transAndScale

	self._freeCamPos = Vec3(headTransform.x, headTransform.y + self._heightOffset, headTransform.z) + (player.soldier.worldTransform.forward * self._frontOffset) + (player.soldier.worldTransform.left * self._horizontalOffset)

	-- Calculate where our camera has to be base on the angles.
	local cosfi = math.cos(yaw)
	local sinfi = math.sin(yaw)

	local costheta = math.cos(pitch)
	local sintheta = math.sin(pitch)

	local cx = self._freeCamPos.x + (2 * sintheta * cosfi)
	local cy = self._freeCamPos.y + (2 * costheta)
	local cz = self._freeCamPos.z + (2 * sintheta * sinfi)

	local freelookVector = Vec3(cx, cy, cz)

	-- Calculate the LookAt transform.
	self._data.transform:LookAtTransform(self._freeCamPos, freelookVector)

end

if G_freelookCamera == nil then
	G_freelookCamera = Freelook()
end

return G_freelookCamera
