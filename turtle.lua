local position = {
  x = 0,
  y = 0,
  z = 0
}

local function updatePosition(movement, axis, func)
  position[axis] = position[axis] + movement
  return(func())
end

local turtleMove = {
  [0] = function() updatePosition( 1, "x", turtle.forward ) end,  -- North
  [1] = function() updatePosition( 1, "y", turtle.forward ) end,  -- East
  [2] = function() updatePosition(-1, "x", turtle.forward ) end,  -- South
  [3] = function() updatePosition(-1, "y", turtle.forward ) end,  -- West
  [4] = function() updatePosition( 1, "z", turtle.up ) end,       -- Up
  [5] = function() updatePosition(-1, "z", turtle.down ) end      -- Down
}

-- Enumeration to store the the different types of message that can be written
local messageLevel = { DEBUG=0, INFO=1, WARNING=2, ERROR=3, FATAL=4 }
local messageLevelNum = { [1]="DEBUG", [2] = "INFO", [3] = "WARNING", [4] = "ERROR", [5] = "FATAL" }
local messageOutputLevels = {         -- What levels to output what to
  print     = messageLevel.DEBUG,      -- What level to print messages to turtle terminal
  broadcast = messageLevel.FATAL,      -- What level to broadcast messages
  file      = messageLevel.FATAL       -- What level to write messages to file
}
local messageOutputFileName = "turtle.log"
-- Message system shamelessly adapted from AustinKK's Advanced Mining Turtle program. Thanks!

-- Variable denotes what direction the turtle is facing
local facing = 0

-- Inventory.
local inventory = {
  count = {},      -- List of slot usage
  space = {},
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

  local dateFormat = "%Y-%m-%d %H:%M:%S"    -- The format to use for outputting date/time.
  local nMSGLevel = msgLevel + 1            -- messageLevel and messageLevelNum is offset slightly. This fixes this offset.
  nMSGLevel = table.concat(messageLevelNum, ", ", nMSGLevel, nMSGLevel)   -- Concats the table for use in the messages.

  if msgLevel >= messageOutputLevels.print then       -- Print to screen
    print(os.date(dateFormat).." ["..nMSGLevel.."] "..message)
  end

  if msgLevel >= messageOutputLevels.broadcast then   -- Broadcast
    rednet.broadcast(os.date(dateFormat).." ["..nMSGLevel.."] "..message)
  end

  if msgLevel >= messageOutputLevels.file and messageOutputFileName ~= nil then -- Write to file
    -- Open file, write message and close file (flush doesn't seem to work!)
    local outputFile = io.open(messageOutputFileName, "a")
    outputFile:write(os.date(dateFormat).." ["..nMSGLevel.."]  "..message.."\n")
    outputFile:close()
  end
end

-- Utility
-- Function will count all inventory slots and also check the space of all slots and put the numbers in the inventory table.
local function countInventory()
  inventory.empty = 0                           -- Reset empty counter
  inventory.full = 0                            -- Reset full counter
  for i = 1,16 do
    inventory.count[i] = turtle.getItemCount(i)
    inventory.space[i] = turtle.getItemSpace(i)
    if inventory.count[i] == 0 then             -- If the slot is empty, add one to the empty counter.
      inventory.empty = inventory.empty + 1
    end
    if inventory.space[i] == 0 then             -- If the slot is full, add one to the full counter.
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
  local actionValues = {
    add = table.insert,
    rem = table.remove
  }

  local validInput = {add = true, rem = true }

  actionValues[action](inventory.scrap, slot)
  table.sort(inventory.scrap)
  writeMessage("(updateScrapBlockList): Slot number "..slot.." "..action" from/to scrap list.", messageLevel.INFO)
  return(true)
end

-- Selects inventory slot and updates the table with what slot that is.
local function selectInventorySlot(slot)
  oldTurtleSelect(slot)
  inventory.selected = slot
  writeMessage("(selectInventorySlot): Inventory slot "..slot.." selected.", messageLevel.DEBUG)
  return(true)
end

-- Turning
-- Function to turn the turtle in a relative direction.
local function turtleTurn(dir)          -- Relative direction (right/left)
  local dirValues = {
    left = turtle.turnLeft,
    right = turtle.turnRight
  }

  local validInput = { left = true, right = true }

  dir = string.lower(dir)

  if not validInput[dir] then
    writeMessage("(turtleTurn): Bad argument. Direction not recognized. Got "..dir, messageLevel.FATAL)
    return(false)                             -- Returns false as input was not correct.
  end

  facing = "left" and facing - 1 or facing + 1  -- Adjusts facing
  facing = math.fmod(facing, 4)                 -- Wraps facing around
  dirValues[dir]()   -- Turns turtle in the direction specified by the argument
  return(facing)    -- Returns the facing as turning is always successful if the input is correct
end

-- turtleFace()
-- Function to turn the turtle in a numerical compass direction using the least amount of turns.
local function turtleFace(dir)                -- Numeric direction
  if facing - dir > 0 then                     -- Shorter to turn left
    repeat
      turtleTurn("left")
    until facing == direction                  -- Turns until correct facing
  elseif facing - dir < 0 then                 -- Shorter to turn right
    repeat
      turtleTurn("right")
    until facing == direction                  -- Turns until correct facing
  end
  return(true)                                  -- Returns true as turning is always possible
end

-- Block manipulation
-- Tries to place a block in the direction specified.
-- Returns boolean value of success.
local function placeBlock(dir)  -- Dir must be a string
  local dirValues = {         -- Functions for each valid input
    forward = turtle.place,
    up = turtle.placeUp,
    down = turtle.placeDown
  }

  -- Valid inputs
  local validInput = { forward = true, up = true, down = true }

  dir = string.lower(dir)

  -- Check to see if the input is valid
  if not validInput[dir] then
    writeMessage("(placeBlock): Bad argument. Direction not recognized. Got: "..dir, messageLevel.FATAL)
    return(false)
  end

  -- Try to place a block. If true, update inventory.
  if dirValues[dir]() then
    inventory.count[inventory.selected] = inventory.count[inventory.selected] - 1
    inventory.space[inventory.selected] = inventory.space[inventory.selected] + 1
    return(true)
  else
    return(false)
  end
end

-- Check if block in dir is a scrap block
-- Returns true if block is a scrap block.
local function detectScrapBlock(dir)
  local dirValues = {
    forward = turtle.compare,
    up = turtle.compareUp,
    down = turtle.compare.Down
  }

  local validInput = { forward = true, up = true, down = true }

  dir = tostring(dir)
  local compare = false

  for index, value in ipairs(inventory.scrap) do
    selectInventorySlot(value)
    if compareDirection[dir] then
      compare = true
    end
  end
  return(compare)
end

-- **********************************************************************************
-- Main Loop
-- **********************************************************************************
local function mainLoop()
  repeat
  -- Check event variables to see if there have been any updates.
  -- Check variables. Is there enough fuel?
  -- If co-ordinates are not correct.
    -- If direction is correct, move once.
    if facing == direction then
      if not turtleMove() then
        -- If movement fails, check if a block is an obstacle
        if turtle.detect() then
          -- Then what? I have no idea...
        end
        -- Is there enough fuel?
        if not turtle.getFuelLevel() > 0 then
          -- Then what? Refuel?
        end
      end
    else  -- Else, turn once.
      turtleTurn(direction)
    end
  -- If co-ordinates are correct.
    -- If direction is correct
      -- Complete task
    -- Else, turn to face
      -- Complete task
  until mainLoopStopValue == true  -- Allow a command to stop the turtle?
end

-- **********************************************************************************
-- Event Loop
-- **********************************************************************************
local function eventLoop()
  local event, p1, p2, p3, p4, p5 = os.pullEventRaw()
  -- Wait for events
    -- Handle events and put details into tables.
    -- Pass events on to mainLoop()
end

-- **********************************************************************************
-- Program
-- **********************************************************************************

--[[ Debugger is not able to run when instructions are given. Remove comment tags to run the program in Minecraft.
-- Open network side
rednet.open("right")
-- Remove bad functions
local os.pullEvent = os.pullEventRaw
local oldTurtleSelect = turtle.select
local turtle.select = selectInventorySlot
-- Load last state from file
-- Run self checks
  -- Get GPS location
  local pos1 = vector.new(gps.locate(2, false))   -- Find first position
  while not turtle.forward do       -- Move forward one block or up until forward is possible.
    turtle.up()
  end
  position = vector.new(gps.locate(2, false))   -- Get new position and add that to position table
  local pos2 = position.x, position.y, position.z   -- Make a new value to do math with
  local vector = pos2 - pos1  -- Find difference between position one and two

  if vector.x > 0 then
    facing = 0  -- North
  elseif vector.x < 0 then
    facing = 2   -- South
  elseif vector.y > 0 then
    facing = 1   -- East
  elseif vector.y < 0 then
    facing = 3    -- West
  end
-- Update inventory
  countInventory()
-- Set selected slot to 1
  selectInventorySlot(1)
-- Start eventLoop() and mainLoop() simoultaneously using CC API.
paralell.waitForAll(mainLoop(), eventLoop())
-- When loops fail/shut down, save state to disk.

-- End program
--]]

local function testFunction(variable)
  print(variable)
  return(true)
end

turtle = { forward = testFunction, turnLeft = testFunction, turnRight = testFunction, place = testFunction, placeUp = testFunction, placeDown = testFunction, select = testFunction }
rednet = { broadcast = testFunction }
