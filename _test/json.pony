use "ponytest"
use "../jay"

use "files"
use url = "../url"

use rpc = "../rpc"

class TestJsonEquality is UnitTest
    fun name(): String => "JsonEquality"
    fun ref apply(h: TestHelper) =>
        h.assert_true(JEq(I64(5), I64(5)))
        h.assert_true(JEq(F64(5.3), F64(5.3)))
        h.assert_true(JEq(None, None))
        h.assert_true(JEq(NotSet, NotSet))
        h.assert_true(JEq("hello", "hello"))
        h.assert_true(JEq(true, true))
        h.assert_true(JEq(JObj, JObj))
        h.assert_true(JEq(JArr, JArr))
        h.assert_true(JEq(JObj * ("a", I64(5)), JObj * ("a", I64(5))))
        h.assert_true(JEq(JArr + I64(5), JArr + I64(5)))

        h.assert_false(JEq(I64(1), I64(2)))
        h.assert_false(JEq(F64(1), F64(2)))
        h.assert_false(JEq(None, false))
        h.assert_false(JEq(NotSet, false))
        h.assert_false(JEq("hello", "bye"))
        h.assert_false(JEq(JObj, JObj * ("foo", "bar")))
        h.assert_false(JEq(JObj * ("foo", "bar"), JObj))
        h.assert_false(JEq(JObj, JArr))
        h.assert_false(JEq(JArr + None, JArr))
        h.assert_false(JEq(JObj * ("foo", "baz"), JObj * ("foo", "bar")))

        h.assert_false(JEq(
            JObj
                * ("foo", JObj
                    * ("bar", false)
                  )
          , JObj
                * ("foo", JObj
                    * ("bar", true)
                )))

        h.assert_false(JEq(
            JObj
                * ("foo", JObj
                    * ("bar", false)
                  )
          , JObj
                * ("foo", JObj
                    * ("bar", false)
                    * ("baz", None)
                )))

        h.assert_true(JEq(
            JObj
                * ("foo", JObj
                    * ("bar", false)
                  )
          , JObj
                * ("foo", JObj
                    * ("bar", false)
                )))
        
        let a = "dummy"
        let b = JObj * ("value", "dummy")
        let abLens = (JLens * "value") / JLens // try obtaining the "value" field of an object, if that doesnt work return the whole thing
        h.assert_true(abLens.equals(a, b), "Expected (" + a.string() + ") `((JLens * 'value') / JLens).equals` (" + b.string() + ")")


class TestLensAssign is UnitTest
    fun name(): String => "LensAssign"
    fun ref apply(h: TestHelper) =>
        let x = JObj
            * ("foo", "bar")
            * ("deep", JObj * ("space", I64(9)))
        
        let foo' = (JLens * "foo")

        let foobazz = (foo' == "bazz")(x)

        try
            h.assert_eq[String](foo'(foobazz as J) as String, "bazz")
        else h.fail("failed")
        end
    
class TestLensChoice is UnitTest
    fun name(): String => "LensChoice"
    fun ref apply(h: TestHelper) =>
        let x = JObj * ("value", "bar")
        let y = "foo"

        let valueLens = (JLens * "value") / JLens

        try
            h.assert_eq[String](valueLens(x) as String, "bar")
            h.assert_eq[String](valueLens(y) as String, "foo")
        else h.fail("failed")
        end
    
class TestLensArray is UnitTest
    fun name(): String => "LensArray"
    fun ref apply(h: TestHelper) =>
        let x = JArr + "markdown" + (JObj * ("language", "en") * ("value", "plain"))

        let valueLens = (JLens.elements() * "value") / JLens

        h.assert_true(JEq(valueLens("tester"), NotSet), "div operator be wrapped by element traversal")
        h.assert_true(JEq((valueLens or JLens)("tester"), "tester"), "or operator should lift the context out of element traversal")

        var result': (J | NotSet) = NotSet
        try
            var result = valueLens(x) as JArr
            result' = result
            h.assert_eq[String](result(0)? as String, "markdown")
            h.assert_eq[String](result(1)? as String, "plain")

            result = (valueLens == "powerranger")(x) as JArr
            result' = result
            var expected = JArr + "powerranger" + (JObj * ("language", "en") * ("value", "powerranger"))
            h.assert_true(JEq(result, expected), "Expected (" + result.string() + ") == (" + expected.string() + ")")
        else h.fail("failed with " + result'.string())
        end
    
class TestLensMap is UnitTest
    fun name(): String => "LensMap"

    fun ref apply(h: TestHelper) =>
        let a = JObj * ("rootPath", "c:\\Users\\Joshua")
        let b = JObj * ("rootUri", "file:///c%3A/Users/Joshua")
        let lens = ((JLens * "rootUri").map[String](UriToPath) or (JLens * "rootPath"))
        //let lens =  (JLens * "rootPath") or (JLens * "rootUri").map[String](UriToPath)

        try
            h.assert_eq[String](lens(a) as String, "c:\\Users\\Joshua")
            h.assert_eq[String](lens(b) as String, "c:\\Users\\Joshua")
        else h.fail("I guess they weren't strings afterall"); h.log(lens(a).string()) ; h.log(lens(b).string())
        end