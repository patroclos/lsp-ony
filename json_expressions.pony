use "json"
use "itertools"
use pc = "collections/persistent"

trait val JExpr
    fun json(): JsonType
    fun string(): String val

// this can't be (JExpr | ...) instead of (JObj | JArr | ...), until [this](https://github.com/ponylang/ponyc/issues/3096) is fixed
type J is (JObj | JArr | String | I64 | F64 | Bool | None)

primitive NotSet is Stringable
    fun string(): String iso ^ => "NotSet".string()

primitive JEq
    fun apply(a: (J | NotSet), b: (J | NotSet)): Bool =>
        match (a, b)
        | (let a': JObj, let b': JObj) =>
            if a'.data.size() != b'.data.size() then return false end
            for (k, v) in a'.data.pairs() do
                try
                    if JEq(b'.data(k)?, v) == false then return false end
                else return false
                end
            end
            true
        | (let a': JArr, let b': JArr) =>
            if a'.data.size() != b'.data.size() then return false end
            var i: USize = 0
            while i < a'.data.size() do
                try 
                    if JEq(a'.data(i)?, b'.data(i)?) == false then
                        return false
                    end
                else return false end
                i = i + 1
            end
            true
        | (let a': I64, let b': I64) => a' == b'
        | (let a': F64, let b': F64) => a' == b'
        | (let a': String, let b': String) => a' == b'
        | (let a': Bool, let b': Bool) => a' == b'
        | (None, None) => true
        | (NotSet, NotSet) => true
        else false
        end

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
    let data: pc.Map[String, J]

    new val create(data': pc.Map[String, J] = pc.Map[String, J]) =>
        data = data'

    new box from_iter(it: Iterator[(String val, J)]) =>
        data = pc.Map[String, J].concat(it)

    fun apply(key: String val): (J | NotSet) =>
        if data.contains(key) then try data(key)? else NotSet end else NotSet end
    
    fun json(): JsonType => json_object()
    
    fun json_object(): JsonObject =>
        let obj = JsonObject(data.size())
        for (k, v) in data.pairs() do
            obj.data(k) = match v
                       | let j: JsonType => j
                       | let j: JExpr => j.json()
                       end
        end
        obj
    
    fun string(): String val => json_object().string()

    fun mul(k: String, v: J): JObj =>
        JObj(data(k) = v)
    
class val JArr is JExpr
    let data: pc.Vec[J]

    new val create(data': pc.Vec[J] = pc.Vec[J]) =>
        data = data'

    new box from_iter(it: Iterator[J]) =>
        data = pc.Vec[J].concat(it)
    
    fun apply(i: USize): J ? => data(i)?

    fun values(): Iterator[J] => data.values()
    
    fun add(v: J): JArr =>
        JArr(data.push(v))
    
    fun json(): JsonType => json_array()

    fun json_array(): JsonArray =>
        let arr = JsonArray(data.size())
        for v in data.values() do
            let v' = match v
                | let j: JsonType => j
                | let j: JExpr => j.json()
                end
            arr.data.push(v')
        end
        arr

    fun string(): String val => json_array().string()

// TRAVERSALS / LENSES

trait val JTraversal
    fun apply(v: J): (J | NotSet)
    fun update(input: J, value: J): (J | NotSet)
    fun val mul(t: JTraversal): JTraversal// => TravCombine(this, t)

    fun val div(alt: JTraversal): JTraversal //=> TravChoice(this, alt)

class val TravCombine is JTraversal
    let _a: JTraversal
    let _b: JTraversal
    new val create(a: JTraversal, b: JTraversal) =>
        _a = a
        _b = b

    //fun val mul(t: JTraversal): JTraversal => TravCombine(this, t)
    fun val mul(t: JTraversal): JTraversal => TravCombine(_a, _b * t)

    fun val div(alt: JTraversal): JTraversal => TravCombine(_a, _b / alt)
    
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

    fun val mul(t: JTraversal): JTraversal => TravCombine(this, t)

    fun val div(alt: JTraversal): JTraversal => TravChoice(this, alt)

    fun apply(v: J): (J | NotSet) =>
        match v
        | let v': JObj => v'(_key)
        else NotSet
        end
    
    fun update(input: J, value: J): (J | NotSet) =>
        try (input as JObj) * (_key, value) else NotSet end

class val TravChoice is JTraversal
    let _a: JTraversal
    let _b: JTraversal

    new val create(a: JTraversal, b: JTraversal) => (_a, _b) = (a, b)

    fun val mul(t: JTraversal): JTraversal => TravCombine(this, t)

    fun val div(alt: JTraversal): JTraversal => TravChoice(this, alt)

    fun apply(v: J): (J | NotSet) =>
        match _a(v)
        | let j: J => j
        | NotSet => _b(v)
        end
    
    fun update(input: J, value: J): (J | NotSet) =>
        match _a.update(input, value)
        | let out: J => out
        | NotSet => _b.update(input, value)
        end

class val TravForEach is JTraversal
    let _subTrav: JTraversal
    new val create(sub: JTraversal = NoTraversal) => _subTrav = sub

    // overriding operators to apply to children of the array
    fun val mul(t: JTraversal): JTraversal =>
        @printf[I32]("A\n".cstring())
        TravForEach(_subTrav * t)

    fun val div(alt: JTraversal): JTraversal =>
        @printf[I32]("B\n".cstring())
        TravForEach(_subTrav / alt)

    fun apply(v: J): (J | NotSet) =>
        match v
        | let arr: JArr =>
            var data: pc.Vec[J] = pc.Vec[J]
            for elem in arr.values() do
                match _subTrav(elem)
                | NotSet => None
                | let e': J => data = data.push(e')
                end
            end
            JArr(data)
        else NotSet
        end
    
    fun update(input: J, value: J): (J | NotSet) =>
        match input
        | let arr: JArr =>
            var data: pc.Vec[J] = pc.Vec[J]
            for elem in arr.values() do
                match _subTrav.update(elem, value)
                | NotSet => None
                | let e': J => data = data.push(e')
                end
            end
            JArr(data)
        else NotSet
        end

class val NoTraversal is JTraversal
    fun apply(v: J): (J | NotSet) => v
    fun update(i: J, v: J) : (J | NotSet) => v

    fun val mul(t: JTraversal): JTraversal => TravCombine(this, t)

    fun val div(alt: JTraversal): JTraversal => TravChoice(this, alt)
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
    
    fun div(alt: JLens): JLens =>
        JLens(_traversal.div(alt._traversal))
    
    fun eq(value: J): Setter =>
        Setter(_traversal, value)

    fun elements(): JLens =>
        JLens(_traversal * TravForEach)
    
    fun equals(a: J, b: J, include_unset: Bool = true): Bool =>
        let a' = apply(a)
        let b' = apply(b)
        match (a', b')
        | (NotSet, NotSet) => include_unset
        else JEq(apply(a), apply(b))
        end
