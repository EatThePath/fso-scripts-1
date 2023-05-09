--Misc Table Copy function
local function DeepTableCopy(orig)

    --From http://lua-users.org/wiki/CopyTable

    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[DeepTableCopy(orig_key)] = DeepTableCopy(orig_value)
        end
        setmetatable(copy, DeepTableCopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end
local CloakSys = {ShipPrototype = {}}
--Some functions for individual ship data tables.

function CloakSys.ShipPrototype:Cloak(state,ship,ctime,player) 
    if (not self.MinEnergy) or (self.MinEnergy and (self.Energy >= self.MinEnergy)) then
        ba.print(ship.Name .. ": CLOAK\n")
        self.Status = state
        ship:addShipEffect("cloak", self.CloakTime * 1000)
        self.Timestamp = ctime + 0.5

        if player then

        mn.runSEXP("( hud-set-text !RightGaugeB! !STATUS: ON! )")
        mn.runSEXP("( fade-in 5000 5 5 5 )")
        gr.setPostEffect("saturation", 20)
        end

        if not self.Shields then
            mn.runSEXP("( shields-off !" .. ship.Name .. "!)")
        end

        mn.runSEXP("( alter-ship-flag !stealth! (true) (false) !" .. ship.Name .. "!)")
        mn.runSEXP("( alter-ship-flag !protect-ship! (true) (false) !" .. ship.Name .. "!)")
        mn.runSEXP("( alter-ship-flag !beam-protect-ship! (true) (false) !" .. ship.Name .. "!)")
        mn.runSEXP("( alter-ship-flag !hidden-from-sensors! (true) (false) !" .. ship.Name .. "!)")
        mn.runSEXP("( turret-lock-all !" .. ship.Name .. "!)")
        mn.runSEXP("( beam-lock-all !" .. ship.Name .. "!)")

        local sound = ad.getSoundentry("Cloak")
        ad.play3DSound(sound, ship.Position)
    elseif self.MinEnergy and (self.Energy < self.MinEnergy) then
        if player then
            ad.playGameSound(10)
        end
    end
end

function CloakSys.ShipPrototype:Decloak(state,ship,ctime,player)
    ba.print(ship.Name .. ": DECLOAK\n")
    self.Status = state
    ship:addShipEffect("decloak", self.CloakTime * 250)
    self.Timestamp = ctime + 0.5
    if player then

        mn.runSEXP("( hud-set-text !RightGaugeB! !STATUS: OFF! )")
        mn.runSEXP("( fade-in 500 192 192 192 )")
        gr.resetPostEffects()
    end

    mn.runSEXP("( alter-ship-flag !stealth! (false) (false) !" .. ship.Name .. "!)")
    mn.runSEXP("( alter-ship-flag !protect-ship! (false) (false) !" .. ship.Name .. "!)")
    mn.runSEXP("( alter-ship-flag !beam-protect-ship! (false) (false) !" .. ship.Name .. "!)")
    mn.runSEXP("( alter-ship-flag !hidden-from-sensors! (false) (false) !" .. ship.Name .. "!)")
    mn.runSEXP("( turret-free-all !" .. ship.Name .. "!)")


    if not self.Shields then
        mn.runSEXP("( shields-on !" .. ship.Name .. "!)")
    end

    local sound = ad.getSoundentry("Decloak")
    ad.play3DSound(sound, ship.Position)
end

function CloakSys.ShipPrototype:AlterState(state)
    --local to self.Ships

    local ship = self.Handle
    local ctime = mn.getMissionTime()
    local player = (self.Sig == CloakSys.Player.Sig)

    if not( ship:isValid() and self.Allowed) then
        return
    end
    if (state == -1) and (self.Status ~= state) then --decloak
        self:Decloak(state,ship,ctime,player)
    elseif state == 1 and (self.Status ~= state) then --cloak
        self:Cloak(state,ship,ctime,player)
    end
end

function CloakSys.ShipPrototype:New(ship,mode_t)
    local t = {}
    t = DeepTableCopy(mode_t)
    t.Allowed = true
    t.Status = -1
    t.Sig = ship:getSignature()
    t.Name = ship.Name
    t.AlterState = self.AlterState
    t.Cloak = self.Cloak
    t.Decloak = self.Decloak
    t.UpdateTimer = self.UpdateTimer
    t.Timer = 0
    t.Timestamp = 0
    t.Handle = ship
    t.Energy = t.MaxEnergy
    return t
end

function CloakSys:Init()

	ba.print("*****Initializing Cloak System...\n")

	self.Enabled = true
	self.Paused = false
	self.Player = {}
    self.ShipsN = {}
	self.Modes = axemParse:ReadJSON("cloak.cfg")
	self.KillAllHumans = false

end

function CloakSys:GetEntryByName(name)

    if name and self.ShipsN[name] then
        if not name then
            return self.Player.Table --will be nil if player doesn't have cloak
        end
    end
    return self.ShipsN[name] --will be nil if ship doesn't have cloak

end

function CloakSys.ShipPrototype:UpdateTimer(mtime,paused, sys)
    if self.timer >= mtime then return end
    local ship = self.Handle

    if not self.Paused then
        if self.Status == 1 and ((self.Energy - self.Rate) >= 0) then
            self.Energy = self.Energy - self.Rate
        elseif self.Status == -1 and ((self.Energy + self.Rate) <= self.MaxEnergy) then
            self.Energy = self.Energy + self.Rate
        end
    end
    --ba.print("AFTER: " .. self.Status .. ": " .. self.Energy .. "\n\n")

    if self.Energy < 1 and self.Status == 1 then
        self:AlterState(-1)
    end

    if self.AI and (self.Name ~= sys.Player.Name) and (self.Status == -1) then

        if not self.AI.Timer then
            self.AI.Timer = 0
        end

        if (self.Energy > self.AI.MinCloak) and (self.AI.Timer < mtime) then
            self:AlterState(1)
        end

    end

    if self.Energy < 0 then
        self.Energy = 0
    end

    if self.Energy > self.MaxEnergy then
        --ba.print("Capping at max energy!\n\n")
        self.Energy = self.MaxEnergy
    end


    self.Timer = mtime + 1
end

function CloakSys:Add(name, mode)
	if not self.Enabled then
		self:Init()
	end

	if self:GetEntryByName(name) then return end

	if not name then
		name = hv.Player.Name
	end

    local ship = mn.Ships[name]
    if not(ship and ship:isValid()) then
        return
    end

    local class = ship.Class.Name

    ba.print("Adding " .. name .. " to cloak list\n")

    if not mode and self.Modes[class] then
        mode = class
    else
        mode = "default"
    end

    ba.print("Cloaking mode chosen: " .. mode .. "\n")

    local t = self.ShipPrototype:New(ship,self.Modes[mode])

    if ship == hv.Player then
        self.Player = {Sig = t.Sig, Name = t.Name, Table = t}
        mn.runSEXP("( hud-set-custom-gauge-active (true) !RightGaugeA! !RightGaugeB! !RightGaugeC! !RightGaugeD!)")
        mn.runSEXP("( hud-set-text !RightGaugeA! !CLOAK! )")
        mn.runSEXP("( hud-set-text !RightGaugeB! !STATUS: OFF! )")
        mn.runSEXP("( hud-set-text !RightGaugeC! !!)")
        mn.runSEXP("( hud-set-text !RightGaugeD! !ALT+Z to Toggle!)")
    end

    if class == "GTF Iapetus" or class == "GTF Iapetus#Zen" then
        mn.runSEXP("( turret-lock !" .. name .. "! !turret01a!)")
        mn.runSEXP("( turret-change-weapon !" .. name .. "! !turret01a! !No Guns! 1 0)")
        Berserk:UpdateUpgradePath()
    end

    self.ShipsN[t.Name] = t
end


function CloakSys:WatchTimer()

	local mtime = mn.getMissionTime()
    for key,data in pairs(self.ShipsN) do
        data:UpdateTimer(mtime,self.Paused,self)
	end

    self:UpdateHUD()
end

function CloakSys:UpdateHUD()
    if not self.Player then return end
    local player = self.Player
    if not(player.Table and player.Name and hv.Player.Name == self.Player.Name) then
        return
    end
    local data = self.Player.Table
    local display = (data.Energy / data.MaxEnergy) * 100

    mn.runSEXP("(hud-set-text !RightGaugeC! !Energy Level: " .. string.format("%3d", display) .. "%!)")
end

function CloakSys:CheckActions(ship, action)
--ship = object signature
--action = 1, fired weapons. 2, used afterburner
    local data = self.ShipsN[ship.Name]
    if data.Status ~= 1 then return end

    if data.WeaponsNull and (action == 1) then
        if data.AI and (ship.Name ~= self.Player.Name) then
            data.AI.Timer = mn.getMissionTime() + data.AI.ActionTimeout
        end
        data:AlterState(-1)
    end
    if data.AfterburnNull and (action == 2) then
        data:AlterState(-1)
    end

end

function CloakSys:MaybeRemove(ship)
    local s = self.ShipsN[ship.Name]
    if not s then return end
    table.remove(self.Ships,s.Index)
    self.ShipsN[s.Name] = nil;

end

function CloakSys:Force(ship, onoff)
	if self.Enabled then
		CloakSys:GetEntryByName(ship):AlterState(onoff)
	end
end

function CloakSys:Exit()

	self.Enabled = nil
    self.ShipsN = nil
    self.ShipsS = nil
	self.Player = nil
	self.Modes = nil
	self.KillAllHumans = nil

end

function CloakSys:GlobalToggle()
	if self.Paused then
		self.Paused = false
	elseif self.Paused == false then
		self.Paused = true
	end
end



function CloakSys:SEXPSet(onoff, mode, ...) 
	for i,data in ipairs(arg) do
		local entry = data[1]
		
		if onoff then
			self:Add(entry.Name, mode)
		else
			self:MaybeRemove(entry)
		end
	end
end

function CloakSys:SEXPForce(onoff, ...) 
	for i,data in ipairs(arg) do
		local entry = data[1]
		
		if onoff then
			self:Force(entry.Name, 1)
		else
			self:Force(entry.Name, -1)
		end
	end
end

function CloakSys:SEXPCheck(...)
    for i,data in ipairs(arg) do
		local entry = self:GetEntryByName(data[1].Name)
        
        if entry == nil or entry.Status ~= 1 then
            return false
        end
    end
    return true
end

function CloakSys:SEXPCheckPlayer(...)
	if self.Player and self.Player.Table and self.Player.Table.Status ~= 1 then
		return false
	end
    return true
end

function CloakSys:GameplayStart()
	self.Ships = {}
	self.Player = {}
end
function CloakSys:Frame()
	if self.Enabled then
		--self:WatchTimer()
	end
end

function CloakSys:KeyRelease()
    if self.Enabled and self.Player and self.Player.Table.Allowed then
		if hv.Key == "Alt-Z" then
			local player = CloakSys.Player.Table
			local newStatus = player.Status * -1
			player:AlterState(newStatus)
		end
	end
end

function CloakSys:MissionEnd()
	if self.Enabled then
		self:Exit()
	end
end

function CloakSys:ShipDeath()
	if self.Enabled then
		self:MaybeRemove(hv.Ship)		
	end
end

function CloakSys:WeaponFire()
    if self.Enabled then
		self:CheckActions(hv.User, 1)
	end
end

function CloakSys:Afterburn()
    if self.Enabled then
		self:CheckActions(hv.Ship, 2)
	end
end

function CloakSys:FireCloakWeapon()
	if mn.getMissionTime() > 0.5 then
		self:Add(hv.User.Name)
	end
end

function CloakSys:SelectCloakWeapon()
    hv.User.SecondaryBanks[1].Armed = true
end

return CloakSys