{aggregate} = require('./aggregate')

{required, defaults} = require("./misc")
message = require('./message')

exports.get_username = aggregate {omit:['client']}, (opts) ->
    opts = defaults opts,
        account_id : required
        client     : required
        aggregate  : undefined
        cb         : required
    opts.client.call
        message     : message.get_usernames(account_ids : [opts.account_id])
        error_event : true
        cb          : (err, resp) ->
            if err
                opts.cb(err)
            else
                opts.cb(undefined, resp.usernames)
    return