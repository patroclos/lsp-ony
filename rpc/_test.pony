use "ponytest"
use "json"

actor Main is TestList
    new create(env: Env) => PonyTest(env, this)
    fun tag tests(test: PonyTest) =>
        test(TestParseReq)
        test(TestParseResponse)

class TestParseReq is UnitTest
    fun name(): String => "ParseRequest"
    fun ref apply(h: TestHelper) =>
        h.assert_no_error({()? =>
            RPC.parse_req("{\"jsonrpc\": \"2.0\", \"method\": \"rpc.testerino\"}")?
            RPC.parse_req("{\"jsonrpc\": \"2.0\", \"id\": 5, \"method\": \"rpc.testerino\"}")?
            RPC.parse_req("{\"jsonrpc\": \"2.0\", \"id\": \"string_id_123\", \"method\": \"rpc.testerino\"}")?
            RPC.parse_req("{\"jsonrpc\": \"2.0\", \"id\": \"string_id_123\", \"method\": \"rpc.testerino\", \"params\": [1, 2, 3.4, [\"some value\"]]}")?
            let r = RPC.parse_req("{\"jsonrpc\": \"2.0\", \"id\": \"string_id_123\", \"method\": \"rpc.testerino\", \"params\": {\"foo\": \"bar\"}}")?
            h.assert_eq[String]((r.params() as JsonObject).data("foo")? as String, "bar", "params wasn't parsed correctly")
            None
        })
        h.assert_error({()? =>
            RPC.parse_req("{\"jsonrpc\": \"2.0\"}")?
            None
        }, "Missing method should produce an error")
        h.assert_error({()? =>
            RPC.parse_req("{\"jsonrpc\": \"2.0\", \"method\": \"rpc.testerino\", \"params\": 5}")?
            None
        }, "Non array or object values for params should produce an error")
        h.assert_error({()? =>
            RPC.parse_req("{\"jsonrpc\": \"2.0\", \"id\": [], \"method\": \"rpc.testerino\"}")?
            None
        }, "Non int or string values for id should produce an error")


class TestParseResponse is UnitTest
    fun name(): String => "ParseResponse"
    fun ref apply(h: TestHelper) =>
        h.assert_no_error({()? =>
            RPC.parse_response("{\"jsonrpc\": \"2.0\", \"result\": 99, \"id\": 99}")?
            RPC.parse_response("{\"jsonrpc\": \"2.0\", \"result\": [], \"id\": \"asdf\"}")?
            RPC.parse_response("{\"jsonrpc\":\"2.0\",\"id\":0,\"result\":{\"capabilities\":{\"textDocumentSync\":2}}}")?
            var response = RPC.parse_response("{\"jsonrpc\": \"2.0\", \"result\": {\"foo\": \"bar\"}, \"id\": null}")?
            h.assert_eq[String]((response.result() as JsonObject).data("foo")? as String, "bar", "result wasn't read correctly")

            response = RPC.parse_response("{\"jsonrpc\": \"2.0\", \"error\": {\"code\": -32700, \"message\": \"Parse error\"}, \"id\": null}")?
            h.assert_eq[I64]((response.result() as RpcError).code, -32700)
            h.assert_eq[String]((response.result() as RpcError).message, "Parse error")
        }, "Failed parsing example cases")
        h.assert_error({()? =>
            RPC.parse_response("{\"jsonrpc\": \"2.0\", \"result\": []}")?
        }, "Missing id field should produce error")
        h.assert_error({()? =>
            RPC.parse_response("{\"jsonrpc\": \"2.0\", \"id\": 1}")?
        }, "Missing result and error field should produce error")