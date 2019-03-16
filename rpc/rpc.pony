use "json"

type RpcId is (String val | I64 val | None)

primitive RPC
    fun val parse_req(str: String val): Request ? =>
        let doc : JsonDoc = JsonDoc .> parse(str)?
        let json : JsonObject = doc.data as JsonObject
        if try json.data("jsonrpc")? as String else "" end != "2.0" then error end
        
        Request(try json.data("id")? else None end as RpcId, json.data("method")? as String, try json.data("params")? else None end as RpcParams)

    fun val parse_response(str: String val): Response ? =>
        let doc : JsonDoc = JsonDoc .> parse(str)?
        let json : JsonObject = doc.data as JsonObject
        if try json.data("jsonrpc")? as String else "" end != "2.0" then error end

        let result: (JsonType | RpcError ref) = try
            json.data("result")?
        else
            RPC.parse_error(json.data("error")? as JsonObject)?
        end
        
        Response(json.data("id")? as RpcId, result)
    
    fun val parse_error(err: JsonObject ref): RpcError ref ? =>
        let code = err.data("code")? as I64
        let message = err.data("message")? as String
        let data = try err.data("data")? else None end
        RpcError(code, message, data)


trait val RpcObject
    fun id(): RpcId
    fun ref json(): JsonObject