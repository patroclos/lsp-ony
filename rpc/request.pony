use "json"

type RpcParams is (JsonArray ref | JsonObject ref | None val)

class Request is RpcObject
    let _id: RpcId
    let _method: String val
    let _params: RpcParams

    new create(id': RpcId, method': String val, params': RpcParams = None) =>
        (_id, _method, _params) = (id', method', params')

    fun id() : RpcId => _id

    fun method() : String val => _method

    fun params() : this->RpcParams => _params

    fun ref json(): JsonObject =>
        let obj = JsonObject
        obj.data("jsonrpc") = "2.0"
        obj.data("method") = method()
        if not is_notification() then
            obj.data("id") = id()
        end

        match _params
        | None => None
        else
            obj.data("params") = _params
        end
        obj

    fun box is_notification(): Bool =>
        match _id
        | None => true
        else false
        end
