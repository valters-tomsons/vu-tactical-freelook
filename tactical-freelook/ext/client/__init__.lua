local Freelook = require('freelook')

Events:Subscribe('Player:Respawn', function(player)
    Freelook:enable()
end)
