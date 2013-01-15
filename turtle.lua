-- **********************************************************************************
-- Constants
-- **********************************************************************************

local directions = {
  [0] = "north",
  [1] = "east",
  [2] = "south",
  [3] = "west",
  north = 0,
  east = 1,
  south = 2,
  west = 3
}

-- Enumeration to store the the different types of message that can be written
local messageLevel = { DEBUG=0, INFO=1, WARNING=2, ERROR=3, FATAL=4 }
local messageLevelNum = { [0] = "DEBUG", [1] = "INFO", [2] = "WARNING", [3] = "ERROR", [4] = "FATAL" }
local messagePrintLevel = messageLevel.INFO            -- Level to print to turtle terminal
local messageBroadcastLevel = messageLevel.ERROR        -- Level to broadcast to server
-- Message system shamelessly adapted from AustinKK's Advanced Mining Turtle program. Thanks!

-- **********************************************************************************
-- Variables
-- **********************************************************************************

-- Variable denotes what direction the turtle is facing
local facing = 0

-- Fuel level. Local values are much faster than global.
local fuel = 0

-- Inventory.
local inventory = {
  list = {},      -- List of slot usage
  left = {},
  scrap = {},     -- List of scrap block slots
  empty = 0,      -- Empty inventory slots
  full = 0,       -- Full inventory slots
  selected = 1    -- Selected inventory slot
}

-- **********************************************************************************
-- Functions
-- **********************************************************************************

-- Messages
-- Writes a message in terminal and broadcasts the error.
local function writeMessage(message, msgLevel)
  if msgLevel >= messagePrintLevel then
    print(messageLevelNum[msgLevel]": "..message)
  end
  if msgLevel >= messageBroadcastLevel then
    rednet.broadcast(messageLevelNum[msgLevel]": "..message)
  end
end

-- Change message levels.
local function changeMessageLevels(Print, Broadcast)
  messagePrintLevel = messageLevel[Print]
  messageBroadcastLevel = messageLevel[Broadcast]
  writeMessage("(changeMessageLevels): Message levels changed. Print level: "..Print..". Broadcast level: "..Broadcast, messageLevel.INFO)
end

-- Utility
-- Convert direction from numerical to string or vice versa.
local function convertDirectionNum(dir)
  if dir == string then
    return(directions[dir])
  elseif dir == 0 or 1 or 2 or 3 then
    return(tonumber(dir))
  else
    writeMessage("(convertDirectionNum): Bad argument. Direction not recognized. Got "..dir, messageLevel.FATAL)
    return(false)
  end
end

-- Function will count all inventory slots and also check the space of all slots and put the numbers in the inventory table.
local function countInventory()
  inventory.empty = 0                           -- Reset empty counter
  inventory.full = 0                            -- Reset full counter
  for i = 1,16 do
    inventory.list[i] = turtle.getItemCount(i)
    inventory.left[i] = turtle.getItemSpace(i)
    if inventory.list[i] == 0 then             -- If the slot is empty, add one to the empty counter.
      inventory.empty = inventory.empty + 1
    end
    if inventory.left[i] == 0 then             -- If the slot is full, add one to the full counter.
      inventory.full = inventory.full + 1
    end
  end
  if inventory.empty >= 2 then
    writeMessage("(countInventory): Low inventory space. "..inventory.empty.." slots left.", messageLevel.INFO)
  end
end

-- Update scrap block inventory list
-- Action has to be "Add" or "Remove"
local function updateScrapBlockList(action, slot)
  table[action](inventory.scrap, slot)
  table.sort(inventory.scrap)
  writeMessage("(updateScrapBlockList): Slot number "..slot.." "..action" from/to scrap list.", messageLevel.INFO)
  return(true)
end

-- Selects inventory slot and updates the table with what slot that is.
local function selectInventorySlot(slot)
  nSlot = tonumber(slot)
  turtle.select(nSlot)
  inventory.selected = nSlot
  writeMessage("(selectInventorySlot): Inventory slot "..slot.." selected.", messageLevel.INFO)
  return(true)
end

-- Turning
-- Function to turn the turtle in a relative direction. Errors if direction is not valid.
local function turtleTurn(direction)          -- Relative direction (right/left)
  if direction ~= "Left" or "Right" then
    writeMessage("(turtleTurn): Bad argument. Direction not recognized. Got "..direction, messageLevel.FATAL)
    return(false)                               -- Returns false as input was not correct.
  end
  if direction == "Left" then
    facing = facing - 1                         -- Subtracts 1 from facing
  elseif direction == "Right" then
    facing = facing + 1                         -- Adds 1 to facing
  end
  writeMessage("turtleTurn): Facing before fmod: "..facing, messageLevel.DEBUG)
  facing = math.fmod(facing, 4)                 -- Wraps facing around'
  writeMessage("turtleTurn): Facing after fmod: "..facing, messageLevel.DEBUG)
  return(turtle.turn[direction]())             -- Turns the turtle in the set direction
end

-- Function to turn the turtle in a numerical compass direction using the least amount of turns.
local function turtleFace(dir)                -- Numeric direction
  if facing - dir > 0 then                     -- Shorter to turn left
    repeat
      turtleTurn("Left")
    until facing == direction                  -- Turns until correct facing
  elseif facing - dir < 0 then                 -- Shorter to turn right
    repeat
      turtleTurn("Right")
    until facing == direction                  -- Turns until correct facing
  end
  return(true)                                  -- Returns true as turning is always possible
end

-- Moving
-- Function to move the turtle in a numerical compass direction. Will use turtleFace to make it move in that specific direction.
local function turtleMove(direction)          -- Numeric direction.
  if not facing == direction then                 -- Checks if the facing is correct.
    turtleFace(direction)                       -- Turns to face if facing is not correct.
  end
  if turtle.forward() then                      -- Commands turtle to move forward and returns boolean success.
    fuel = fuel - 1                             -- Subtracts 1 from fuel level
    return(true)                                -- Turtle has moved. Returns true.
  else
    return(false)                               -- Turtle has not moved. Return false.
  end
end

-- Block manipulation
-- Tries to place a block in the direction specified. If no direction is specified, block is placed in front of the turtle.
-- Returns boolean value of success.
local function placeBlock(dir)
  if dir == nil then                           -- If direction is not specified, use forward facing.
    if turtle.place() then
      inventory.list[inventory.selected] = inventory.list[inventory.selected] - 1
      inventory.left[inventory.selected] = inventory.left[inventory.selected] + 1
      return(true)
    else
      return(false)
    end
  elseif dir == "Up" or "Down" then           -- If direction is up or down, place the block.
    if turtle.place[dir]() then
      inventory.list[inventory.selected] = inventory.list[inventory.selected] - 1
      inventory.left[inventory.selected] = inventory.left[inventory.selected] + 1
      return(true)
    else
      return(false)
    end
  else
    writeMessage("(placeBlock): Bad argument. Direction not recognized. Got "..dir, messageLevel.FATAL)
    return(false)
  end
end

-- Check if block in dir is a scrap block
local function detectScrapBlock(dir)
  local compare = false
  if dir == nil then
    for index, value in ipairs(inventory.scrap) do
      selectInventorySlot(value)
      if turtle.compare() then
        compare = true
      end
    end
  elseif dir == "Up" or "Down" then
    for index, value in ipairs(inventory.scrap) do
      if turtle.compare[dir]() then
        compare = true
      end
    end
  end
  return(compare)
end

-- Mine the block in the specified direction
local function mineBlock(dir)
  return(turtle.dig[dir]())
end
