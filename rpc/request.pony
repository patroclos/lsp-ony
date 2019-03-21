use "../jay"

type RpcParams is (JArr val | JObj val | None val)

class val Request is RpcObject
    let _id: RpcId
    let _method: String val
    let _params: RpcParams

    new val create(id': RpcId, method': String val, params': RpcParams = None) =>
        (_id, _method, _params) = (id', method', params')

    fun id() : RpcId => _id

    fun method() : String val => _method

    fun params() : this->RpcParams => _params

    fun json(): JObj =>
        JObj
            * ("jsonrpc", "2.0")
            * ("method", method())
            * ("id", if is_notification() then NotSet else id() end)
            * ("params", match _params
                         | None => NotSet
                         else params()
                         end)

    fun box is_notification(): Bool =>
        match _id
        | None => true
        else false
        end
