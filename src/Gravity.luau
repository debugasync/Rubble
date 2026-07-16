-- Rubble / Gravity

-- Variables
local NewInstance = Instance.new
local Vector3New = Vector3.new

local Workspace = game:GetService("Workspace")


-- Constants
local Bodies = {
    Earth = 9.80665,
    Moon = 1.62,
    Mars = 3.72076,
    Mercury = 3.7,
    Venus = 8.87,
    Jupiter = 24.79,
    Saturn = 10.44,
    Uranus = 8.69,
    Neptune = 11.15,
    Pluto = 0.62,
    Sun = 274.0
}

local DefaultScale = 20


-- Namespace
local Gravity = {}

Gravity.Bodies = Bodies
Gravity.StudsPerMetre = DefaultScale


-- Values
do
    Gravity.SetScale = function(StudsPerMetre)
        Gravity.StudsPerMetre = StudsPerMetre
    end

    Gravity.Metres = function(Body)
        return Bodies[Body] or Bodies.Earth
    end

    Gravity.Studs = function(Body)
        return Gravity.Metres(Body) * Gravity.StudsPerMetre
    end
end


-- World
do
    Gravity.SetWorld = function(Body)
        local Value = Gravity.Studs(Body or "Earth")
        Workspace.Gravity = Value

        return Value
    end

    Gravity.Earth = function()
        return Gravity.SetWorld("Earth")
    end

    Gravity.Reset = function()
        Workspace.Gravity = 196.2

        return 196.2
    end
end


-- Per part
do
    Gravity.Apply = function(Part, Body)
        Gravity.Remove(Part)

        local Target = Gravity.Studs(Body)
        local World = Workspace.Gravity
        local Mass = Part.AssemblyMass

        local Attachment = NewInstance("Attachment")
        Attachment.Name = "RubbleGravity"
        Attachment.Parent = Part

        local Force = NewInstance("VectorForce")
        Force.Name = "RubbleGravityForce"
        Force.Attachment0 = Attachment
        Force.RelativeTo = Enum.ActuatorRelativeTo.World
        Force.ApplyAtCenterOfMass = true
        Force.Force = Vector3New(0, (World - Target) * Mass, 0)
        Force.Parent = Part

        return Force
    end

    Gravity.Remove = function(Part)
        local Force = Part:FindFirstChild("RubbleGravityForce")
        if Force then
            Force:Destroy()
        end

        local Attachment = Part:FindFirstChild("RubbleGravity")
        if Attachment then
            Attachment:Destroy()
        end
    end
end


return Gravity
