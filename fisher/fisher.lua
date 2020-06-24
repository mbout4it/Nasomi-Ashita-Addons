_addon.name = 'fisher';
_addon.author = 'scoobwrecks';
_addon.version = '0.0.0.1';
_addon.command = 'fisher';

require 'common';
require 'struct';
require 'stringex';
require 'mathex';

-- Create a file name based on the current date and time..
local date = os.date('*t');
local fish_start_time = os.clock();
local name = string.format('packets_%d.%d.%d-%d_%d_%d.txt', date['month'], date['day'], date['year'], date['hour'], date['min'], date['sec']);
local working_path = string.format('%s/%s/%s/%s/', AshitaCore:GetAshitaInstallPath(), 'addons', 'fisher','logs');
if (not ashita.file.dir_exists(working_path)) then
	ashita.file.create_dir(working_path);
end
local file = working_path .. name;
local catch_limit = 0;
local num_catches = 0;
local cast_num = 0;
local items_caught = 0;
local monsters_caught = 0;
local fish_dur = 0.00;
local catch_monster = false;
local catch_unknown = true;
local fisher_running = false;
local monster_on_line = false;
local item_on_line = false;
local cast_out = false;

----------------------------------------------------------------------------------------------------
-- Configurations
----------------------------------------------------------------------------------------------------
local default_config =
{
    fishersettings =
    {
        -- enable catching monsters
        ['catch_monster'] =
        {
            enabled = false
        },
		-- enable catching monsters
        ['catch_unknown'] =
        {
            enabled = true
        },
		-- catch limit
        ['catch_limit'] =
        {
            number = 0
        },
    }
};

local fisher_config = default_config;

----------------------------------------------------------------------------------------------------
-- func: log
-- desc: Writes the given string to the current packet log file.
----------------------------------------------------------------------------------------------------
local function log(str, ...)
    -- Print the data to the console window..
    --io.write(str:format(...), '\n');
    
    -- Open the packet log for appending..
    local f = io.open(file, 'a');
    if (f == nil) then
        return;
    end
    
    -- Write the data to the file..
    f:write(str:format(...));
    f:flush();
    f:close();
end

----------------------------------------------------------------------------------------------------
-- func: hexdump
-- desc: Converts the given packet string to a hex dump output for easier reading.
----------------------------------------------------------------------------------------------------
local function hexdump(str, align, indent)
    local ret = '';
    
    -- Loop the data string in steps..
    for x = 1, #str, align do
        local data = str:sub(x, x + 15);
        ret = ret .. string.rep(' ', indent);
        ret = ret .. data:gsub('.', function(c) return string.format('%02X ', string.byte(c)); end);
        ret = ret .. string.rep(' ', 3 * (16 - #data));
        ret = ret .. ' ' .. data:gsub('%c', '.');
        ret = ret .. '\n';
    end
    
    -- Fix percents from breaking string.format..
    ret = string.gsub(ret, '%%', '%%%%');
    ret = ret .. '\n';
    
    return ret;
end

---------------------------------------------------------------------------------------------------
-- func: is_inventory_full
-- desc: Returns if the inventory is full.
---------------------------------------------------------------------------------------------------
local function is_inventory_full()
    local inventory = AshitaCore:GetDataManager():GetInventory();
    
    -- Obtain the current inventory count..
    local count = 0;
    for x = 1, 80 do
        local item = inventory:GetItem(0, x);
        if (item.Id ~= 0) then
            count = count + 1;
        end
    end

    -- Determine if we have a full inventory..
    if (count >= (inventory:GetContainerMax(0) - 2)) then
        return true;
    end
    
    return false;
end

---------------------------------------------------------------------------------------------------
-- func: stop_fishing
-- desc: stop fishing variables set
---------------------------------------------------------------------------------------------------
local function stop_fishing(reason)
	fisher_running = false;
	num_catches = 0;
	cast_num = 0;
	items_caught = 0;
	monsters_caught = 0;
	monster_on_line = false;
    cast_out = false;
	item_on_line = false;
	print('Fishing stopped due to '..reason..'.');
end

---------------------------------------------------------------------------------------------------
-- func: cast_line
-- desc: casts line
---------------------------------------------------------------------------------------------------
local function cast_line()
	if fisher_running then
		--AshitaCore:GetChatManager():QueueCommand('/fps 1', CommandInputType.Typed);
		AshitaCore:GetChatManager():QueueCommand('/fish', CommandInputType.Typed);
		cast_num = cast_num + 1;
		cast_out = true;
	end
end

---------------------------------------------------------------------------------------------------
-- func: input_fish_command
-- desc: will initiate cast if able to
---------------------------------------------------------------------------------------------------
local function input_fish_command(recast)
	if fisher_running then
		fish_dur = os.clock() - fish_start_time;

		if is_inventory_full() then
			stop_fishing('full inventory');
		elseif (fish_dur / 60.00) >= 20.00 then
			ashita.misc.play_sound(string.format('%s\\sounds\\%s', _addon.path, 'fatigue.wav'));
			stop_fishing('fatigue');
		else
			ashita.timer.once(recast,cast_line);
		end
	end
end

local function catchFish(fish_id, catch_key)
	fish_dur = os.clock() - fish_start_time;
	local playerindex = GetPlayerEntity().TargetIndex;
	local playerid = AshitaCore:GetDataManager():GetParty():GetMemberServerId(0);
	--FISHACTION_CHECK    = 2,  // This is always the first 0x110 packet. //
    --FISHACTION_FINISH   = 3,  // This is the next 0x110 after 0x115. //
    --FISHACTION_END      = 4,
    --FISHACTION_WARNING  = 5   // This is the 0x110 packet if the time is going on too long. //
	local action = 3;
	local stamina = 0;
	if monster_on_line then
		stamina = 300; -- 300 is amount sent to give up on catch
		monsters_caught = monsters_caught + 1;
	elseif item_on_line then
		items_caught = items_caught + 1;
	end
	local newpacket = struct.pack("bbbbIIHBBI", 0x10, 0x0B, 0x00, 0x00, playerid, stamina, playerindex, action, 0, catch_key):totable();
	num_catches = num_catches + 1;
	monster_on_line = false;
	item_on_line = false;
    cast_out = false;
	local catchpct = (math.round((num_catches/cast_num),4) * 100.00);
	local itempct = (math.round((items_caught/cast_num),4) * 100.00);
	local monsterpct = (math.round((monsters_caught/cast_num),4) * 100.00);
	local mindur = math.round((fish_dur/60.00),2);
	print('Casts: '..cast_num..' | Catches: '..num_catches..' | Catch rate '..catchpct..
		  '% | Item rate '..itempct..'% | Monster rate '..monsterpct..'% |  Duration(minutes): '..mindur);
	AddOutgoingPacket(0x110,newpacket);
	input_fish_command(7.0);
end

----------------------------------------------------------------------------------------------------
-- func: command
-- desc: Event called when a command was entered.
----------------------------------------------------------------------------------------------------
ashita.register_event('command', function(command, ntype)
    -- Ensure we should handle this command..
    local args = command:args();
    if (args[1] ~= '/fisher') then
        return false;
    end
    
    -- Start fishing, a 3rd argument can be provided for catch limit
    if (#args > 1 and args[2] == 'start') then
        if #args > 2 then 
			catch_limit = tonumber(args[3])
		end
		if catch_limit > 0 then
			print('Fishing started with catch limit of '..catch_limit..'.');
		else
			print('Fishing started with no catch limit.');
		end
		fish_start_time = os.clock();
		fisher_running = true;
		cast_line();
    end
    -- Stop fishing
    if (#args > 1 and args[2] == 'stop') then
		stop_fishing('stop command request')
    end
	
    return true;
end);

---------------------------------------------------------------------------------------------------
-- func: load
-- desc: Event called when the addon is being loaded.
---------------------------------------------------------------------------------------------------
ashita.register_event('load', function()
    -- Load the configuration file..
    fisher_config = ashita.settings.load_merged(_addon.path .. '/settings/fisher.json', fisher_config);
	    -- Ensure the main config table exists..
    if (fisher_config == nil or type(fisher_config) ~= 'table') then
        print('fisher_config not loaded from path ' ..addon.path '/settings/fisher.json');
		AshitaCore:GetChatManager():QueueCommand('/addon unload fisher', CommandInputType.Typed);
    end
    
    -- Ensure the fishersettings table exists..
    if (fisher_config.fishersettings == nil or type(fisher_config.fishersettings) ~= 'table') then
        print('fisher_config not set up correctly in ' ..addon.path '/settings/fisher.json');
		AshitaCore:GetChatManager():QueueCommand('/addon unload fisher', CommandInputType.Typed);
    end

    if (fisher_config['fishersettings']['catch_monster'] ~= nil) then
		-- set up monster catching flag
		catch_monster = fisher_config['fishersettings']['catch_monster'].enabled;
		if catch_monster then
			print('Monster catching is enabled.');
		else
			print('Monster catching is disabled.');
		end
	end
	
    if (fisher_config['fishersettings']['catch_unknown'] ~= nil) then
		-- set up monster catching flag
		catch_unknown = fisher_config['fishersettings']['catch_unknown'].enabled;
		if catch_unknown then
			print('Unknown catching is enabled.');
		else
			print('Unknown catching is disabled.');
		end
	end
	
    if (fisher_config['fishersettings']['catch_limit'] ~= nil) then
		-- set up default catch limit
		catch_limit = fisher_config['fishersettings']['catch_limit'].number;
		if catch_limit > 0 then
			print('Fishing catch limit is set to '..catch_limit..'.');
		else
			print('No fishing catch limit.');
		end
	end
end);

---------------------------------------------------------------------------------------------------
-- func: incoming_text
-- desc: Event called when the addon is asked to handle an incoming chat line.
---------------------------------------------------------------------------------------------------
ashita.register_event('incoming_text', function(mode, chat)
	-- track if monster on line
	if chat:lower():contains('something clamps onto your line ferociously!') and cast_out then
		monster_on_line = true;
	-- track if item on line
	elseif chat:lower():contains('you feel something pulling at your line.') and cast_out then
		item_on_line = true;
	-- no bite schedule a new cast
	elseif chat:lower():contains('you didn\'t catch anything.') then
		input_fish_command(6.0);
	end
    return false;
end );

---------------------------------------------------------------------------------------------------
-- func: incoming_packet
-- desc: Called when our addon receives an incoming packet.
---------------------------------------------------------------------------------------------------
ashita.register_event('incoming_packet', function(id, size, packet, packet_modified, blocked)
    --log('[Server -> Client] Id: %04X | Size: %d\n', id, size);
	--log('%s',hexdump(packet,16,4));
	--bite info packet is 0x115
	if (id == 0x115) then
		local stamina = struct.unpack('H',packet,0x04+1);
		local arrowDelay = struct.unpack('H',packet,0x06+1);
		local regen = struct.unpack('H',packet,0x08+1);
		local response = struct.unpack('H',packet,0x0A+1);
		local hitDmg = struct.unpack('H',packet,0x0C+1);
		local missRegen = struct.unpack('H',packet,0x0E+1);
		local gameTime = struct.unpack('H',packet,0x10+1);
		--sense: 0 = small fish/item, 1 = large fish/monster (battle music), 2 = small fish/item (lightbulb), 3 = large fish/monster (lightbulb + fight music)
		local sense = struct.unpack('B',packet,0x12+1);
		local catchId = struct.unpack('I',packet,0x14+1);
		local catchDelay = (math.random(500,1000)/100);
		if monster_on_line then
			--print('Releasing monster.');
			catchFish(stamina,catchId)
			--ashita.timer.once(catchDelay,catchFish,stamina,catchId);
		else
			--print('Catching fish in '..catchDelay..' seconds.');
			catchFish(stamina,catchId)
			--ashita.timer.once(catchDelay,catchFish,stamina,catchId);
		end
	end
	return false;
end);