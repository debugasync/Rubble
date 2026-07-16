-- Rubble

-- Variables
local Vector3New = Vector3.new
local NewInstance = Instance.new
local NewSequence = NumberSequence.new
local NewColorSequence = ColorSequence.new
local NewRange = NumberRange.new
local NewTweenInfo = TweenInfo.new
local Random = math.random
local Sin = math.sin
local Cos = math.cos
local Acos = math.acos
local Clamp = math.clamp
local Min = math.min
local Max = math.max
local Floor = math.floor
local TwoPi = math.pi * 2
local Sort = table.sort
local Spawn = task.spawn
local Delay = task.delay

local GeometryService = game:GetService("GeometryService")
local TweenService = game:GetService("TweenService")
local PhysicsService = game:GetService("PhysicsService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Gravity = require(script.Gravity)


-- Constants
local ZeroVector = Vector3.zero
local ZeroColor = Color3.new()

local StructureGroup = "RubbleStructure"
local DebrisGroup = "RubbleDebris"


-- Defaults
local Defaults = {
    Mode = "Chip",
    Health = 100,
    ChunkSize = 2.4,
    ChipRadius = 2.4,
    ChipPower = 0.015,
    ChipPerHit = 6,
    CollapseAt = 0.15,
    Scorch = 0.16,
    MaxCells = 80,
    FarSpacing = 2.4,
    ImpactCount = 24,
    ImpactRadius = 2.4,
    ImpactSkew = 1.6,
    MaxFragments = 90,
    ImpactForce = 55,
    Penetration = 20,
    Scatter = 8,
    Spin = 12,
    Lifetime = 6,
    Fade = 1,
    CollisionGroup = nil,
    Gravity = nil,
    Dust = nil,
    OnDamage = nil,
    OnBreak = nil
}


-- Namespaces
local Rubble = {}

local Sites = {}
local Debriswork = {}
local Structures = {}

local Registry = {}
local CellLookup = {}


-- Debris container
local Container = NewInstance("Folder")
Container.Name = "Rubble"
Container.Parent = Workspace

local StandingFolder = NewInstance("Folder")
StandingFolder.Name = "RubbleStructures"
StandingFolder.Parent = Workspace


-- Collision groups
do
    pcall(function()
        PhysicsService:RegisterCollisionGroup(StructureGroup)
        PhysicsService:RegisterCollisionGroup(DebrisGroup)
    end)

    pcall(function()
        PhysicsService:CollisionGroupSetCollidable(DebrisGroup, StructureGroup, false)
        PhysicsService:CollisionGroupSetCollidable(DebrisGroup, DebrisGroup, false)
    end)
end


-- Sites
do
    Sites.RandomUnit = function()
        local Theta = Random() * TwoPi
        local Phi = Acos(2 * Random() - 1)
        local SinPhi = Sin(Phi)

        return Vector3New(SinPhi * Cos(Theta), SinPhi * Sin(Theta), Cos(Phi))
    end

    Sites.Clamp = function(Value, Half)
        if Value > Half then
            return Half
        end

        if Value < -Half then
            return -Half
        end

        return Value
    end

    Sites.Uniform = function(Part, Spacing, Cap)
        local Size = Part.Size
        local HalfX = Size.X * 0.5
        local HalfY = Size.Y * 0.5
        local HalfZ = Size.Z * 0.5

        local CountX = Max(1, Floor(Size.X / Spacing))
        local CountY = Max(1, Floor(Size.Y / Spacing))
        local CountZ = Max(1, Floor(Size.Z / Spacing))

        local StepX = Size.X / CountX
        local StepY = Size.Y / CountY
        local StepZ = Size.Z / CountZ

        local Points = {}
        local PointsIndex = 0

        for Ix = 1, CountX do
            for Iy = 1, CountY do
                for Iz = 1, CountZ do
                    if PointsIndex >= Cap then
                        return Points, PointsIndex
                    end

                    PointsIndex += 1
                    Points[PointsIndex] = Vector3New(
                        -HalfX + (Ix - 0.5) * StepX + (Random() - 0.5) * StepX * 0.5,
                        -HalfY + (Iy - 0.5) * StepY + (Random() - 0.5) * StepY * 0.5,
                        -HalfZ + (Iz - 0.5) * StepZ + (Random() - 0.5) * StepZ * 0.5
                    )
                end
            end
        end

        return Points, PointsIndex
    end

    Sites.Generate = function(Part, ImpactLocal, Config)
        local Size = Part.Size
        local HalfX = Size.X * 0.5
        local HalfY = Size.Y * 0.5
        local HalfZ = Size.Z * 0.5

        local Radius = Config.ImpactRadius
        local Skew = Config.ImpactSkew

        local Points = {}
        local PointsIndex = 0

        for i = 1, Config.ImpactCount do
            local Distance = Radius * (Random() ^ Skew)
            local Offset = Sites.RandomUnit() * Distance

            PointsIndex += 1
            Points[PointsIndex] = Vector3New(
                Sites.Clamp(ImpactLocal.X + Offset.X, HalfX),
                Sites.Clamp(ImpactLocal.Y + Offset.Y, HalfY),
                Sites.Clamp(ImpactLocal.Z + Offset.Z, HalfZ)
            )
        end

        local Spacing = Config.FarSpacing
        local CountX = Max(1, Floor(Size.X / Spacing))
        local CountY = Max(1, Floor(Size.Y / Spacing))
        local CountZ = Max(1, Floor(Size.Z / Spacing))

        local StepX = Size.X / CountX
        local StepY = Size.Y / CountY
        local StepZ = Size.Z / CountZ

        for Ix = 1, CountX do
            for Iy = 1, CountY do
                for Iz = 1, CountZ do
                    local Point = Vector3New(
                        -HalfX + (Ix - 0.5) * StepX,
                        -HalfY + (Iy - 0.5) * StepY,
                        -HalfZ + (Iz - 0.5) * StepZ
                    )

                    if (Point - ImpactLocal).Magnitude <= Radius then
                        continue
                    end

                    if PointsIndex >= Config.MaxFragments then
                        break
                    end

                    PointsIndex += 1
                    Points[PointsIndex] = Point
                end
            end
        end

        return Points, PointsIndex
    end

    Sites.ToWorld = function(Part, Points, Count)
        local CFrame = Part.CFrame
        local World = {}

        for i = 1, Count do
            World[i] = CFrame:PointToWorldSpace(Points[i])
        end

        return World
    end
end


-- Debris
do
    Debriswork.Launch = function(Piece, Impact, Direction, Config)
        Piece.Anchored = false
        Piece.CanCollide = true
        Piece.CollisionGroup = Config.CollisionGroup or DebrisGroup
        Piece.Parent = Container

        local Offset = Piece.Position - Impact
        local Distance = Offset.Magnitude
        local Outward = Distance > 0.001 and Offset / Distance or Sites.RandomUnit()
        local Falloff = Config.ImpactRadius / (Distance + Config.ImpactRadius)
        local SizeFactor = Clamp(Config.ChunkSize / Max(Piece.Size.Magnitude, 0.1), 0.55, 2.2)

        Piece.AssemblyLinearVelocity = Outward * Config.ImpactForce * Falloff * SizeFactor
            + Direction * Config.Penetration
            + Sites.RandomUnit() * Config.Scatter

        Piece.AssemblyAngularVelocity = Sites.RandomUnit() * Config.Spin * SizeFactor

        if Config.Gravity then
            Gravity.Apply(Piece, Config.Gravity)
        end

        local Life = Config.Lifetime + Random() * Config.Fade
        Debris:AddItem(Piece, Life)

        if Config.Fade > 0 then
            Delay(Max(Life - Config.Fade, 0), function()
                if Piece.Parent then
                    TweenService:Create(Piece, NewTweenInfo(Config.Fade), {Transparency = 1}):Play()
                end
            end)
        end
    end

    Debriswork.Dust = function(Position, Config)
        local Tint = typeof(Config.Dust) == "Color3" and Config.Dust or Color3.fromRGB(148, 138, 126)

        local Host = NewInstance("Part")
        Host.Anchored = true
        Host.CanCollide = false
        Host.Transparency = 1
        Host.Size = Vector3New(0.1, 0.1, 0.1)
        Host.CFrame = CFrame.new(Position)
        Host.Parent = Container

        local Emitter = NewInstance("ParticleEmitter")
        Emitter.Color = NewColorSequence(Tint)
        Emitter.Size = NewSequence({
            NumberSequenceKeypoint.new(0, 1.2),
            NumberSequenceKeypoint.new(1, 4)
        })
        Emitter.Transparency = NewSequence({
            NumberSequenceKeypoint.new(0, 0.3),
            NumberSequenceKeypoint.new(1, 1)
        })
        Emitter.Lifetime = NewRange(0.6, 1.2)
        Emitter.Speed = NewRange(3, 8)
        Emitter.SpreadAngle = Vector2.new(180, 180)
        Emitter.Rotation = NewRange(0, 360)
        Emitter.Rate = 0
        Emitter.Parent = Host
        Emitter:Emit(20)

        Debris:AddItem(Host, 2)
    end
end


-- Structures
do
    Structures.Prefracture = function(Part, Config)
        local Points, Count = Sites.Uniform(Part, Config.ChunkSize, Config.MaxCells)

        if Count < 2 then
            return nil
        end

        local World = Sites.ToWorld(Part, Points, Count)

        local Success, Fragments = pcall(function()
            return GeometryService:FragmentAsync(Part, World)
        end)

        if not Success or not Fragments then
            return nil
        end

        local Structure = {
            Config = Config,
            Cells = {},
            Total = 0,
            Alive = 0
        }

        for i = 1, #Fragments do
            local Cell = Fragments[i].Instance
            Cell.Anchored = true
            Cell.CollisionGroup = StructureGroup
            Cell:SetAttribute("Destructible", true)
            Cell.Parent = StandingFolder

            Structure.Total += 1
            Structure.Alive += 1
            Structure.Cells[Structure.Total] = Cell
            CellLookup[Cell] = Structure
        end

        Part:Destroy()

        return Structure
    end

    Structures.Chip = function(Structure, Position, Damage, Direction)
        local Config = Structure.Config
        local Radius = Config.ChipRadius + (Damage or 0) * Config.ChipPower
        local Hit = Direction or ZeroVector

        local Candidates = {}
        local CandidatesIndex = 0

        for i = 1, Structure.Total do
            local Cell = Structure.Cells[i]

            if Cell and Cell.Parent then
                local Distance = (Cell.Position - Position).Magnitude

                if Distance <= Radius then
                    CandidatesIndex += 1
                    Candidates[CandidatesIndex] = {Index = i, Cell = Cell, Distance = Distance}
                end
            end
        end

        Sort(Candidates, function(Left, Right)
            return Left.Distance < Right.Distance
        end)

        local Removed = Min(CandidatesIndex, Config.ChipPerHit)

        for i = 1, Removed do
            local Entry = Candidates[i]

            Structure.Cells[Entry.Index] = nil
            Structure.Alive -= 1
            CellLookup[Entry.Cell] = nil

            Debriswork.Launch(Entry.Cell, Position, Hit, Config)
        end

        local ScorchRadius = Radius * 1.5

        for i = 1, Structure.Total do
            local Cell = Structure.Cells[i]

            if Cell and Cell.Parent and (Cell.Position - Position).Magnitude <= ScorchRadius then
                Cell.Color = Cell.Color:Lerp(ZeroColor, Config.Scorch)
            end
        end

        if Config.Dust then
            Debriswork.Dust(Position, Config)
        end

        if Config.OnDamage then
            Config.OnDamage(Structure, Structure.Alive, Structure.Total, Position)
        end

        if Structure.Alive <= Structure.Total * Config.CollapseAt then
            Structures.Collapse(Structure, Position, Hit)
        end
    end

    Structures.Collapse = function(Structure, Position, Direction)
        local Config = Structure.Config

        for i = 1, Structure.Total do
            local Cell = Structure.Cells[i]

            if Cell and Cell.Parent then
                Structure.Cells[i] = nil
                CellLookup[Cell] = nil

                Debriswork.Launch(Cell, Position, Direction, Config)
            end
        end

        Structure.Alive = 0

        if Config.OnBreak then
            Config.OnBreak(Structure, Position, Structure.Total)
        end
    end
end


-- Break
do
    Rubble.Break = function(Part, Position, Direction)
        local Data = Registry[Part]
        Registry[Part] = nil

        local Config = Data and Data.Config or Defaults
        local Impact = Position or Part.Position
        local Hit = Direction or ZeroVector

        Spawn(function()
            local ImpactLocal = Part.CFrame:PointToObjectSpace(Impact)
            local Points, Count = Sites.Generate(Part, ImpactLocal, Config)

            if Count < 2 then
                return
            end

            local World = Sites.ToWorld(Part, Points, Count)

            local Success, Fragments = pcall(function()
                return GeometryService:FragmentAsync(Part, World)
            end)

            if not Success or not Fragments then
                return
            end

            for i = 1, #Fragments do
                Debriswork.Launch(Fragments[i].Instance, Impact, Hit, Config)
            end

            if Config.Dust then
                Debriswork.Dust(Impact, Config)
            end

            if Config.OnBreak then
                Config.OnBreak(Part, Impact, #Fragments)
            end

            Part:Destroy()
        end)
    end
end


-- Api
do
    Rubble.Register = function(Part, Options)
        local Config = {}

        for Key, Value in next, Defaults do
            Config[Key] = Value
        end

        if Options then
            for Key, Value in next, Options do
                Config[Key] = Value
            end
        end

        Registry[Part] = {
            Config = Config,
            Health = Config.Health,
            MaxHealth = Config.Health
        }

        return Registry[Part]
    end

    Rubble.Unregister = function(Part)
        Registry[Part] = nil
    end

    Rubble.IsRegistered = function(Part)
        return Registry[Part] ~= nil or CellLookup[Part] ~= nil
    end

    Rubble.Hit = function(Instance, Position, Damage, Direction)
        local Data = Registry[Instance]

        if Data then
            if Data.Config.Mode == "Chip" then
                Registry[Instance] = nil

                Spawn(function()
                    local Structure = Structures.Prefracture(Instance, Data.Config)

                    if Structure then
                        Structures.Chip(Structure, Position, Damage, Direction)
                    end
                end)

                return
            end

            Data.Health -= Damage or 0

            if Data.Config.OnDamage then
                Data.Config.OnDamage(Instance, Max(Data.Health, 0), Data.MaxHealth, Position)
            end

            if Data.Health <= 0 then
                Rubble.Break(Instance, Position, Direction)
            end

            return
        end

        local Structure = CellLookup[Instance]

        if Structure then
            Structures.Chip(Structure, Position, Damage, Direction)
        end
    end

    Rubble.Clear = function()
        for _, Piece in next, Container:GetChildren() do
            Piece:Destroy()
        end
    end
end


Rubble.Gravity = Gravity

return Rubble
