use url = "./url"
use "files"

primitive UriToPath
    fun apply(uri': String): (String | None) =>
        try
            let uri = url.URL.build(uri')?
            if uri.scheme == "file" then
                var path: String val = (url.URLEncode.decode(uri.path)?).trim(1)
                path = try Path.canonical(path)? else Path.clean(path) end

                ifdef windows then
                // uppercase drive letters TODO: Path.canonical should probably do this
                    try
                        if path(1)? == ':' then
                            let drive = path(0)?
                            if (drive >= 'a') and (drive <= 'z') then
                                path = recover path.clone() .> update_offset(0, (drive - 'a') + 'A')? end
                            end
                        end
                    end
                end
                path
            else None
            end
        end