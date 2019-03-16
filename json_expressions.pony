use "json"
use "itertools"
use pc = "collections/persistent"

trait val JExpr
    fun json(): JsonType
    fun string(): String =>
        let j = json()
        match j
        | let j': JsonArray => j'.string()
        | let j': JsonObject => j'.string()
        | let j': (F64 | I64 | Bool | None | String) => j'.string()
        end

type J is (JExpr | String | I64 | F64 | Bool | None)

primitive NotSet is Stringable
    fun string(): String iso^ => "NotSet".string()

primitive JParse
    fun apply(json: JsonType): J =>
        match json
        | let v: (I64 | F64 | String | Bool | None) => v
        | let j: JsonObject ref => JObjParse(j)
        | let j: JsonArray ref => JArrParse(j)
        end

primitive JObjParse
    fun apply(json: JsonObject ref): JObj val =>
        var data = pc.Map[String, J]
        for (k, v) in json.data.pairs() do
            data = data(k) = JParse(v)
        end

        JObj(data)

primitive JArrParse
    fun apply(json: JsonArray ref): JArr val =>
        var data = pc.Vec[J]
        for v in json.data.values() do
            data = data.push(JParse(v))
        end
        JArr(data)

class val JObj is JExpr
    let _data: pc.Map[String, J]

    new val create(data: pc.Map[String, J] = pc.Map[String, J]) =>
        _data = data

    new box from_iter(it: Iterator[(String val, J)]) =>
        _data = pc.Map[String, J].concat(it)

    fun apply(key: String val): (J | NotSet) =>
        if _data.contains(key) then try _data(key)? else NotSet end else NotSet end
    
    fun json(): JsonType =>
        let obj = JsonObject(_data.size())
        for (k, v) in _data.pairs() do
            obj.data(k) = match v
                       | let j: JsonType => j
                       | let j: JExpr => j.json()
                       end
        end
        obj

    fun mul(k: String, v: J): JObj =>
        JObj(_data(k) = v)
    
    fun box div(k: String): JObjLookup => JObjLookup(this, k)


class val JArr is JExpr
    let _data: pc.Vec[J]

    new val create(data: pc.Vec[J] = pc.Vec[J]) =>
        _data = data

    new box from_iter(it: Iterator[J]) =>
        _data = pc.Vec[J].concat(it)
    
    fun add(v: J): JArr =>
        JArr(_data.push(v))
    
    fun json(): JsonType =>
        let arr = JsonArray(_data.size())
        for v in _data.values() do
            let v' = match v
                | let j: JsonType => j
                | let j: JExpr => j.json()
                end
            arr.data.push(v')
        end
        arr

trait box JLookup
    fun is_set(): Bool
    fun apply(): (J | NotSet)
    fun div(key: String val): JLookup

class box JLookupEmpty is JLookup
    fun is_set(): Bool => false
    fun apply(): (J | NotSet) => NotSet
    fun div(key: String val): JLookup => JLookupEmpty

class box JObjLookup is JLookup
    let _obj: JObj box
    let _key: String val

    new box create(obj: JObj box, key: String val) =>
        _obj = obj
        _key = key
    
    fun apply(): (J | NotSet) => _obj(_key)

    fun is_set(): Bool => try apply() as NotSet ; false else true end

    fun div(k: String): JLookup =>
        try
            match apply() as J
            | let f: JObj => JObjLookup(f, k)
            else JLookupEmpty
            end
        else JLookupEmpty
        end

trait val JTraversal
    fun apply(v: J): (J | NotSet)
    fun update(input: J, value: J): (J | NotSet)
    fun val mul(t: JTraversal): JTraversal => TravCombine(this, t)

class val TravCombine is JTraversal
    let _a: JTraversal
    let _b: JTraversal
    new val create(a: JTraversal, b: JTraversal) =>
        _a = a
        _b = b
    
    fun apply(v: J): (J | NotSet) =>
        match _a(v)
        | NotSet => NotSet
        | let a': J => _b(a')
        end
    
    fun update(input: J, value: J): (J | NotSet) =>
        try
            _a.update(input, _b.update(_a(input) as J, value) as J)
        else NotSet
        end

class val TravObjKey is JTraversal
    let _key: String val

    new val create(key: String val) =>
        _key = key

    fun apply(v: J): (J | NotSet) =>
        match v
        | let v': JObj => v'(_key)
        else NotSet
        end
    
    fun update(input: J, value: J): (J | NotSet) =>
        try (input as JObj) * (_key, value) else NotSet end
    
class val NoTraversal is JTraversal
    fun apply(v: J): (J | NotSet) => v
    fun update(i: J, v: J) : (J | NotSet) => v
    // ?

class val Setter
    let _traversal: JTraversal
    let _value: J

    new val create(trav: JTraversal, value: J) =>
        _traversal = trav
        _value = value

    fun apply(input: J): (J | NotSet) =>
        _traversal.update(input, _value)

class val JLens
    let _traversal: JTraversal

    new val create(trav: JTraversal = NoTraversal) =>
        _traversal = trav
    
    fun apply(input: J): (J | NotSet) =>
        _traversal(input)
    
    fun update(input: J, value: J): (J | NotSet) =>
        _traversal.update(input, value)

        // examples, "baz" being the value to be put some place
        // trav[0] = (input, "baz")
        // trav[0] = (input, trav[1] = (trav[0](input), "baz"))
        // trav[0] = (input, trav[1] = (trav[0](input), trav[2] = (trav[1](trav[0](input)))))
    
    fun mul(key: String val): JLens =>
        JLens(_traversal * TravObjKey(key))
    
    fun eq(value: J): Setter =>
        Setter(_traversal, value)

/*
use "json"
use "itertools"
use pc = "collections/persistent"

trait val JExpr
    fun json(): JsonType
    fun string(): String =>
        let j = json()
        match j
        | let j': JsonArray => j'.string()
        | let j': JsonObject => j'.string()
        | let j': (F64 | I64 | Bool | None | String) => j'.string()
        end

type J is (JExpr | String | I64 | F64 | Bool | None)

primitive NotSet is Stringable
    fun string(): String iso^ => "NotSet".string()

primitive JParse
    fun apply(json: JsonType): J =>
        match json
        | let v: (I64 | F64 | String | Bool | None) => v
        | let j: JsonObject ref => JObjParse(j)
        | let j: JsonArray ref => JArrParse(j)
        end

primitive JObjParse
    fun apply(json: JsonObject ref): JObj val =>
        var data = pc.Map[String, J]
        for (k, v) in json.data.pairs() do
            data = data(k) = JParse(v)
        end

        JObj(data)

primitive JArrParse
    fun apply(json: JsonArray ref): JArr val =>
        var data = pc.Vec[J]
        for v in json.data.values() do
            data = data.push(JParse(v))
        end
        JArr(data)

class val JObj is JExpr
    let _data: pc.Map[String, J]

    new val create(data: pc.Map[String, J] = pc.Map[String, J]) =>
        _data = data

    new box from_iter(it: Iterator[(String val, J)]) =>
        _data = pc.Map[String, J].concat(it)

    fun apply(key: String val): (J | NotSet) =>
        if _data.contains(key) then try _data(key)? else NotSet end else NotSet end
    
    fun json(): JsonType =>
        let obj = JsonObject(_data.size())
        for (k, v) in _data.pairs() do
            obj.data(k) = match v
                       | let j: JsonType => j
                       | let j: JExpr => j.json()
                       end
        end
        obj

    fun mul(k: String, v: J): JObj =>
        JObj(_data(k) = v)
    
    fun box div(k: String): JObjLookup => JObjLookup(this, k)


class val JArr is JExpr
    let _data: pc.Vec[J]

    new val create(data: pc.Vec[J] = pc.Vec[J]) =>
        _data = data

    new box from_iter(it: Iterator[J]) =>
        _data = pc.Vec[J].concat(it)
    
    fun add(v: J): JArr =>
        JArr(_data.push(v))
    
    fun json(): JsonType =>
        let arr = JsonArray(_data.size())
        for v in _data.values() do
            let v' = match v
                | let j: JsonType => j
                | let j: JExpr => j.json()
                end
            arr.data.push(v')
        end
        arr

trait box JLookup
    fun is_set(): Bool
    fun apply(): (J | NotSet)
    fun div(key: String val): JLookup

class box JLookupEmpty is JLookup
    fun is_set(): Bool => false
    fun apply(): (J | NotSet) => NotSet
    fun div(key: String val): JLookup => JLookupEmpty

class box JObjLookup is JLookup
    let _obj: JObj box
    let _key: String val

    new box create(obj: JObj box, key: String val) =>
        _obj = obj
        _key = key
    
    fun apply(): (J | NotSet) => _obj(_key)

    fun is_set(): Bool => try apply() as NotSet ; false else true end

    fun div(k: String): JLookup =>
        try
            match apply() as J
            | let f: JObj => JObjLookup(f, k)
            else JLookupEmpty
            end
        else JLookupEmpty
        end

class TestCase
    fun ref do_stuff(): JsonType =>
        (JObj
            * ("capabilities", JObj 
                * ("textDocumentSync", JObj
                    * ("openClose", true)
                    * ("change", I64(1))
                    * ("save", JObj
                        * ("includeText", true)
                      )
                  )
                * ("completionProvider", JObj
                    * ("resolveProvider", true)
                  )
              )
        )
        (JObj
            * ("foo", "bar")
            * ("nested", JObj
                * ("value", I64(5))
              )
            * ("some_array", JArr + true + false + None)
        ).json()
        */