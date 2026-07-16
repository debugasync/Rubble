-- Rubble

-- Variables
local Vector3New = Vector3.new
local NewInstance = Instance.new
local Random = math.random
local Sin = math.sin
local Cos = math.cos
local Acos = math.acos
local Sqrt = math.sqrt
local Min = math.min
local Max = math.max
local Floor = math.floor
local Pi = math.pi
local TwoPi = math.pi * 2
local Spawn = task.spawn
local Insert = table.insert

local GeometryService = game:GetService("GeometryService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")


-- Constants
local ZeroVector = Vector3.zero


-- Defaults
local Defaults = {
    Health = 100,
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
    OnDamage = nil,
    OnBreak = nil
}


-- Namespaces
local Rubble = {}

local Sites = {}
local Registry = {}
local Debriswork = {}


-- Debris container
local Container = NewInstance("Folder")
Container.Name = "Rubble"
Container.Parent = Workspace


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
            local Direction = Sites.RandomUnit()
            local Offset = Direction * Distance

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
                        -HalfX + (Ix - 0.5) * StepX + (Random() - 0.5) * StepX * 0.6,
                        -HalfY + (Iy - 0.5) * StepY + (Random() - 0.5) * StepY * 0.6,
                        -HalfZ + (Iz - 0.5) * StepZ + (Random() - 0.5) * StepZ * 0.6
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
end


-- Debris
do
    Debriswork.Launch = function(Piece, Impact, Direction, Config)
        Piece.Anchored = false
        Piece.CanCollide = true
        Piece.Parent = Container

        if Config.CollisionGroup then
            Piece.CollisionGroup = Config.CollisionGroup
        end

        local Offset = Piece.Position - Impact
        local Distance = Offset.Magnitude
        local Outward = Distance > 0.001 and Offset / Distance or Sites.RandomUnit()

        local Falloff = Config.ImpactRadius / (Distance + Config.ImpactRadius)
        local Scatter = Sites.RandomUnit() * Config.Scatter

        Piece.AssemblyLinearVelocity = Outward * Config.ImpactForce * Falloff
            + Direction * Config.Penetration
            + Scatter

        Piece.AssemblyAngularVelocity = Sites.RandomUnit() * Config.Spin

        Debris:AddItem(Piece, Config.Lifetime + Random() * Config.Fade)
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

            local World = {}
            for i = 1, Count do
                World[i] = Part.CFrame:PointToWorldSpace(Points[i])
            end

            local Success, Fragments = pcall(function()
                return GeometryService:FragmentAsync(Part, World)
            end)

            if not Success or not Fragments then
                return
            end

            for i = 1, #Fragments do
                local Piece = Fragments[i].Instance
                Debriswork.Launch(Piece, Impact, Hit, Config)
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
        return Registry[Part] ~= nil
    end

    Rubble.GetHealth = function(Part)
        local Data = Registry[Part]

        if not Data then
            return nil
        end

        return Data.Health, Data.MaxHealth
    end

    Rubble.SetHealth = function(Part, Health)
        local Data = Registry[Part]

        if Data then
            Data.Health = Health
        end
    end

    Rubble.Heal = function(Part, Amount)
        local Data = Registry[Part]

        if Data then
            Data.Health = Min(Data.Health + Amount, Data.MaxHealth)
        end
    end

    Rubble.Hit = function(Part, Position, Damage, Direction)
        local Data = Registry[Part]

        if not Data then
            return
        end

        Data.Health -= Damage or 0

        if Data.Config.OnDamage then
            Data.Config.OnDamage(Part, Max(Data.Health, 0), Data.MaxHealth, Position)
        end

        if Data.Health <= 0 then
            Rubble.Break(Part, Position, Direction)
        end
    end

    Rubble.Clear = function()
        for _, Piece in next, Container:GetChildren() do
            Piece:Destroy()
        end
    end
end


return Rubble
