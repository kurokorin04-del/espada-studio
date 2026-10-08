-- ServerScriptService/EspadaStudioServerPro.lua
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

-- Setup Folders
local mapFolder = workspace:FindFirstChild("EspadaMap")
if not mapFolder then
	mapFolder = Instance.new("Folder")
	mapFolder.Name = "EspadaMap"
	mapFolder.Parent = workspace
end

local remote = ReplicatedStorage:FindFirstChild("EspadaRemote")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "EspadaRemote"
	remote.Parent = ReplicatedStorage
end

local dataStore = DataStoreService:GetDataStore("EspadaStudioLevels_v2")

-- ===== UNDO/REDO SYSTEM =====
local undoStack = {}
local redoStack = {}
local MAX_UNDO_STEPS = 50

local function serializeMap()
	local objects = {}
	for _, obj in ipairs(mapFolder:GetChildren()) do
		if obj:IsA("BasePart") then
			table.insert(objects, {
				Name = obj.Name,
				Size = {obj.Size.X, obj.Size.Y, obj.Size.Z},
				Position = {obj.Position.X, obj.Position.Y, obj.Position.Z},
				Rotation = {obj.Rotation.X, obj.Rotation.Y, obj.Rotation.Z},
				Color = {obj.Color.R, obj.Color.G, obj.Color.B},
				Material = tostring(obj.Material),
				Shape = obj:IsA("Part") and tostring(obj.Shape) or nil,
				Anchored = obj.Anchored,
				CanCollide = obj.CanCollide,
				ID = obj:GetAttribute("EspadaID") or game:GetService("HttpService"):GenerateGUID(false),
			})
		end
	end
	return objects
end

local function deserializeMap(list)
	for _, child in ipairs(mapFolder:GetChildren()) do
		if child:IsA("BasePart") then
			child:Destroy()
		end
	end

	for _, data in ipairs(list or {}) do
		local customData = {
			Size = Vector3.new(data.Size[1], data.Size[2], data.Size[3]),
			Color = Color3.new(data.Color[1], data.Color[2], data.Color[3]),
			Rotation = Vector3.new(data.Rotation[1] or 0, data.Rotation[2] or 0, data.Rotation[3] or 0),
		}

		if data.Material then
			local ok, mat = pcall(function()
				return Enum.Material[data.Material]
			end)
			if ok and mat then
				customData.Material = mat
			end
		end

		if data.Shape then
			local ok, shape = pcall(function()
				return Enum.PartType[data.Shape]
			end)
			if ok and shape then
				customData.Shape = shape
			end
		end

		local part = createPartFromType(data.Name, Vector3.new(
			data.Position[1], data.Position[2], data.Position[3]
		), customData)

		part:SetAttribute("EspadaID", data.ID)
		part.Anchored = true
	end
end

local function addUndoState()
	table.insert(undoStack, serializeMap())
	if #undoStack > MAX_UNDO_STEPS then
		table.remove(undoStack, 1)
	end
	redoStack = {}
end

-- ===== PART CREATION =====
function createPartFromType(toolName, pos, customData)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	part.Position = pos
	part.Name = toolName
	part.Tag = "EspadaObject"

	if toolName == "Platform" then
		part.Size = Vector3.new(8, 1, 8)
		part.Color = Color3.fromRGB(96, 204, 128)
	elseif toolName == "Coin" then
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(1.2, 1.2, 1.2)
		part.Color = Color3.fromRGB(255, 200, 0)
		part.Material = Enum.Material.Neon
	elseif toolName == "Spike" then
		part.Size = Vector3.new(4, 1, 4)
		part.Color = Color3.fromRGB(255, 70, 70)
	elseif toolName == "Spawn" then
		part.Size = Vector3.new(4, 1, 4)
		part.Color = Color3.fromRGB(95, 150, 255)
		part.Material = Enum.Material.Neon
	elseif toolName == "Goal" then
		part.Size = Vector3.new(4, 4, 4)
		part.Color = Color3.fromRGB(255, 80, 220)
		part.Material = Enum.Material.Neon
	elseif toolName == "Checkpoint" then
		part.Size = Vector3.new(4, 1, 4)
		part.Color = Color3.fromRGB(70, 255, 220)
		part.Material = Enum.Material.Neon
	else
		part.Size = Vector3.new(8, 1, 8)
		part.Color = Color3.fromRGB(255, 255, 255)
	end

	if customData then
		if customData.Size then part.Size = customData.Size end
		if customData.Color then part.Color = customData.Color end
		if customData.Material then part.Material = customData.Material end
		if customData.Shape then part.Shape = customData.Shape end
		if customData.Rotation then part.Rotation = customData.Rotation end
	end

	part.Parent = mapFolder
	return part
end

-- ===== SERVER EVENT HANDLER =====
remote.OnServerEvent:Connect(function(player, action, payload)
	if action == "PlaceObject" then
		addUndoState()
		local toolName = payload.ToolName
		local pos = payload.Position
		local customData = payload.CustomData or {}

		createPartFromType(toolName, pos, customData)

	elseif action == "DeleteObject" then
		addUndoState()
		local part = payload.Part
		if part and part:IsDescendantOf(workspace) then
			part:Destroy()
		end

	elseif action == "UpdateObject" then
		local part = payload.Part
		if part and part:IsDescendantOf(workspace) then
			if payload.Position then part.Position = payload.Position end
			if payload.Size then part.Size = payload.Size end
			if payload.Rotation then part.Rotation = payload.Rotation end
			if payload.Color then part.Color = payload.Color end
		end

	elseif action == "DuplicateObject" then
		addUndoState()
		local part = payload.Part
		if part and part:IsDescendantOf(workspace) then
			local newPart = part:Clone()
			newPart.Position = part.Position + Vector3.new(3, 0, 3)
			newPart.Parent = mapFolder
		end

	elseif action == "SaveLevel" then
		local levelName = payload.LevelName or "DefaultLevel"
		local encoded = HttpService:JSONEncode(serializeMap())
		local success, err = pcall(function()
			dataStore:SetAsync("player_" .. tostring(player.UserId) .. "_" .. levelName, encoded)
		end)
		if success then
			remote:FireClient(player, "LevelSaved", {LevelName = levelName})
		end

	elseif action == "LoadLevel" then
		local levelName = payload.LevelName or "DefaultLevel"
		local success, data = pcall(function()
			return dataStore:GetAsync("player_" .. tostring(player.UserId) .. "_" .. levelName)
		end)

		if success and data then
			local decoded = HttpService:JSONDecode(data)
			deserializeMap(decoded)
			remote:FireClient(player, "LevelLoaded", {LevelName = levelName})
		end

	elseif action == "GetLevelList" then
		local success, levels = pcall(function()
			return dataStore:GetAsync("player_" .. tostring(player.UserId) .. "_levels")
		end)
		if success and levels then
			remote:FireClient(player, "LevelList", HttpService:JSONDecode(levels))
		else
			remote:FireClient(player, "LevelList", {})
		end

	elseif action == "Undo" then
		if #undoStack > 0 then
			table.insert(redoStack, serializeMap())
			local state = table.remove(undoStack)
			deserializeMap(state)
		end

	elseif action == "Redo" then
		if #redoStack > 0 then
			table.insert(undoStack, serializeMap())
			local state = table.remove(redoStack)
			deserializeMap(state)
		end

	elseif action == "ClearMap" then
		addUndoState()
		for _, child in ipairs(mapFolder:GetChildren()) do
			if child:IsA("BasePart") then
				child:Destroy()
			end
		end
	end
end)

-- ===== SETUP FLOOR =====
local floor = workspace:FindFirstChild("EspadaFloor")
if not floor then
	floor = Instance.new("Part")
	floor.Name = "EspadaFloor"
	floor.Size = Vector3.new(200, 1, 200)
	floor.Position = Vector3.new(0, -1, 0)
	floor.Anchored = true
	floor.CanCollide = true
	floor.Color = Color3.fromRGB(50, 50, 60)
	floor.Material = Enum.Material.SmoothPlastic
	floor.TopSurface = Enum.SurfaceType.Smooth
	floor.BottomSurface = Enum.SurfaceType.Smooth
	floor.Tag = "EspadaFloor"
	floor.Parent = workspace
end

print("✅ Espada Studio Server Pro Ready!")
