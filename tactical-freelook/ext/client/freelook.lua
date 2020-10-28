class('Freelook')

function Freelook:__init()

	self._freelookKey = InputDeviceKeys.IDK_LeftAlt

	self._twoPi = math.pi * 2
	self._halfPi = math.pi / 2

	self._rotationSpeed = 1.916686
	self._fov = 75

	-- These exactly match the vertical soldier aiming angles
	self._minPitch = -70.0 * (math.pi / 180.0)
	self._maxPitch = 85.0 * (math.pi / 180.0)

	self._freeCamYaw = 0.0
	self._freeCamPitch = 0.0
	self._freeCamPos = nil

	self._lockYaw = false
	self._authoritativeYaw = 0.0

	self._useFreelook = false

	self._data = nil
	self._entity = nil

	Hooks:Install('Input:PreUpdate', 100, self, self._onInputPreUpdate)
	Events:Subscribe('Engine:Update', self, self._onUpdate)
	Events:Subscribe('Level:Destroy', self, self._onLevelDestroy)
end

function Freelook:enable()
	if self._entity ~= nil then
		return
	end

	-- Create data for freelook camera entity
	self._data = CameraEntityData()
	self._data.fov = self._fov
	self._data.enabled = true
	self._data.priority = 99999
	self._data.nameId = 'freelook-cam'
	self._data.transform = LinearTransform()

	-- And then create the camera entity.
	self._entity = EntityManager:CreateEntity(self._data, self._data.transform)
	self._entity:Init(Realm.Realm_Client, true)
end

function Freelook:_takeControl()
	if self._entity ~= nil then
		self._useFreelook = true
		self._entity:FireEvent('TakeControl')
	end
end

function Freelook:_releaseControl()
	self._useFreelook = false

	if self._entity ~= nil then
		self._entity:FireEvent('ReleaseControl')
	end
end

function Freelook:_onLevelDestroy()
	self._releaseControl()

	if self._entity == nil then
		return
	end

	-- Destroy the camera entity.
	self._entity:Destroy()
	self._entity = nil
	self._freeCamPos = nil
	self._useFreelook = nil
end

function Freelook:_onInputPreUpdate(hook, cache, dt)
	local player = PlayerManager:GetLocalPlayer()

	if player == nil then
		return
	end

	if not player.alive then
		return
	end

	-- Check if the player is locking the camera.
	if self._freelookKey ~= InputDeviceKeys.IDK_None and InputManager:IsKeyDown(self._freelookKey) then
		if not self._useFreelook and player.input ~= nil then
			self._useFreelook = true

			self._freeCamYaw = player.input.authoritativeAimingYaw
			self._freeCamPitch = player.input.authoritativeAimingPitch
		end
	elseif self._useFreelook then
		self._useFreelook = false
	end

	-- If we are locking then prevent the player from looking around.
	if self._useFreelook then
		player:EnableInput(EntryInputActionEnum.EIAYaw, false)
		player:EnableInput(EntryInputActionEnum.EIAPitch, false)

		if not self._lockYaw then
			self._authoritativeYaw = self._freeCamYaw
			self._lockYaw = true
		end

		self:_hideHead(true)
		self:_takeControl();
	else
		self:_releaseControl();
		player:EnableInput(EntryInputActionEnum.EIAYaw, true)
		player:EnableInput(EntryInputActionEnum.EIAPitch, true)

		self._lockYaw = false

		self:_hideHead(false)
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

		local minYaw = self._authoritativeYaw - self._halfPi
		local maxYaw = self._authoritativeYaw + self._halfPi

		while self._freeCamYaw < minYaw do
			self._freeCamYaw = minYaw
		end

		while self._freeCamYaw > maxYaw do
			self._freeCamYaw = maxYaw
		end

	end
end

function Freelook:_hideHead(hide)
	local player = PlayerManager:GetLocalPlayer()

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

	local yaw = self._freeCamYaw
	local pitch = self._freeCamPitch


	-- Fix angles so we're looking at the right thing.
	yaw = yaw - math.pi / 2
	pitch = pitch + math.pi / 2

	local playerHeadQuat = player.soldier.ragdollComponent:GetInterpolatedWorldTransform(46)
	local headTransform = playerHeadQuat.transAndScale
	
	self._freeCamPos = Vec3(headTransform.x, headTransform.y, headTransform.z)

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

if g_FreelookCamera == nil then
	g_FreelookCamera = Freelook()
end

return g_FreelookCamera