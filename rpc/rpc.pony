use "../jay"

type RpcId is (String val | I64 val | None)

primitive RPC
	fun val parse_req(str: String val): Request ? =>
		let json: JObj = JParse.from_string(str)? as JObj
		if (json("jsonrpc") as String != "2.0") then error end

		let id = match json("id")
			| NotSet => None
			| let rpcId: RpcId => rpcId
			else error end
		
		Request(id,
				json("method") as String,
				try json("params") as RpcParams else None end)

	fun val parse_response(str: String val): Response ? =>
		let json: JObj = JParse.from_string(str)? as JObj
		if (json("jsonrpc") as String != "2.0") then error end

		let result: (J | RpcError val) = try json("result") as J
			else
				RPC.parse_error(json("error") as JObj)?
			end
		
		Response(json.data("id")? as RpcId, result)
	
	fun val is_response(json: J): Bool =>
		try
			let j = json as JObj
			j.data.contains("result") or j.data.contains("error")
		else false
		end
	
	fun val parse_error(err: JObj box): RpcError val ? =>
		let code = err("code") as I64
		let message = err("message") as String
		let data = try err("data") as J else None end
		RpcError(code, message, data)


trait val RpcObject
	fun id(): RpcId
	fun json(): JObj