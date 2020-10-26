local Freelook = require('freelook')

Events:Subscribe('Player:Respawn', function(player)
    print('Player:Respawn fired')
    Freelook:enable()
end)