local uniquesId = 0
return function ()
    uniquesId = uniquesId + 1
    return uniquesId
end