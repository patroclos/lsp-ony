use "ponytest"
use ".."

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