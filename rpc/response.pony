use "json"

class Response is RpcObject
    let _id: RpcId
    let _result: (JsonType | RpcError ref)

    new create(id': RpcId, result': (JsonType | RpcError ref)) =>
        (_id, _result) = (id', result')
    
    fun id(): RpcId => _id
    fun result(): (this->JsonType | this->RpcError ref) => _result

    fun ref json(): JsonObject =>
        let obj = JsonObject
        obj.data("jsonrpc") = "2.0"
        obj.data("id") = id()
        
        match _result
        | let err: RpcError ref => obj.data("error") = err.json()
        | let res: JsonType => obj.data("result") = res
        end
        obj