use "json"

class RpcError
    let code: I64 val
    let message: String val
    let data: JsonType

    new create(code': I64, message': String val, data': JsonType = None) =>
        (code, message, data) = (code', message', data')
    
    fun ref with_data(data': JsonType): RpcError ref^ =>
        RpcError(code, message, data')
    
    fun ref with_message(message': String val): RpcError ref^ =>
        RpcError(code, message', data)
    
    fun ref json(): JsonObject =>
        let obj = JsonObject
        obj.data("code") = code
        obj.data("message") = message
        obj.data("data") = data
        obj