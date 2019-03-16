use "logger"
use "json"
use "buffered"
use "collections"

use rpc = "rpc"

class LspReader is InputNotify
    let _log: Logger[String]
    var _lspNotify: LspNotify = NoLspNotify
    let _rb: Reader = Reader
    var _mode: _ReadMode = _ModeReadHeader
    var _headers: Map[String, (USize val | String val)] = Map[String, (USize val | String val)]

    new create(log: Logger[String]) =>
        _log = log
    
    fun ref notify(lspNotify: LspNotify) =>
        _lspNotify = lspNotify
    
    fun ref reset() =>
        _rb.clear()
        _mode = _ModeReadHeader
        _headers.clear()

    fun ref apply(data: Array[U8] iso): None val =>
        let arr: Array[U8] val = consume data
        _rb.append(arr)
        _notify()

    
    fun ref _notify() =>
        match _mode
        | _ModeReadHeader => _notify_header()
        | _ModeReadBody => _notify_body()
        end

    fun ref _notify_header() =>
        let line': (String val | None) = try _rb.line()? else None end
        match line'
        | None => None
        | let line: String val =>
            if line.size() == 0 then
                _mode = _ModeReadBody
            else
                try
                    let i_delim = line.find(": ")?
                    let field_name = line.trim(0, i_delim.usize())
                    let value = line.trim(i_delim.usize() + 2)
                    _headers(field_name) = try value.usize()? else value end
                end
            end

            if _rb.size() > 0 then _notify() end
        end

    fun ref _notify_body() =>
        try
            let block_size = _headers("Content-Length")? as USize
            let block = _rb.block(block_size)?

            let block_str = String.from_array(consume block)
            let block_json = JsonDoc .> parse(block_str)?

            let obj = if rpc.RPC.is_response(block_json) then rpc.RPC.parse_response(block_str)? else rpc.RPC.parse_req(block_str)? end

            match obj
            | let req: rpc.Request => _lspNotify.requested(req)
            | let res: rpc.Response => _lspNotify.responded(res)
            end

            _headers.clear()
            _mode = _ModeReadHeader
        end
