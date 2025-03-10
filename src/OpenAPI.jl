const SCHEMA_DIR = RelocatableFolders.@path joinpath(ROOT, "schema")
const VERSIONS = Dict([
    "2.0" => "v2",
    "3.0" => "v3.0",
    "3.1" => "v3.1",
])

mutable struct OpenAPI
    version::String
    info::Dict{String, Any}
    paths::Dict{String, Any}
    optional_fields::Dict{String, Any}

    function OpenAPI(version::String, info::Dict{String,<:Any}; optional_fields::Dict{String, Any}=Dict{String, Any}())
        this = new()
        this.version = version
        this.info = info
        this.optional_fields = optional_fields
        this.paths = Dict{String, Any}()
        return this
    end
end

function openApiToDict(openApi::OpenAPI)::Dict{String, Any}
    spec_dict = Dict{String, Any}()
    version_name = openApi.version == "2.0" ? "swagger" : "openapi"
    spec_dict[version_name] = openApi.version
    spec_dict["info"] = openApi.info
    spec_dict["paths"] = openApi.paths
    for (key, val) in openApi.optional_fields
        spec_dict[key] = val
    end
    return spec_dict
end

struct InvalidSwaggerSpecificationException <:Exception
    issue::JSONSchema.SingleIssue
end


function Base.showerror(io::IO, e::InvalidSwaggerSpecificationException)
    issue = e.issue
    println(io, """\n
    Validation failed:
    path:         $(isempty(issue.path) ? "top-level" : issue.path)
    instance:     $(issue.x)
    schema key:   $(issue.reason)
    schema value: $(issue.val)""")
end


function validate_spec(spec::Dict{String, Any})

    @assert (haskey(spec, "swagger") || haskey(spec, "openapi")) "Field 'swagger' (v2) or 'openapi' (v3) is missing"

    version_name = haskey(spec, "swagger") ? "swagger" : "openapi"
    version = spec[version_name]
    if version == "3.0"
        spec[version_name] = "3.0.0"
    elseif startswith(version, "3.0")
        version = "3.0"
    elseif version == "3.1"
        spec[version_name] = "3.1.0"
        version == "3.1.0" # OpenAPI 3.1.x gives an error if the version is in the format <major>.<minor>
    elseif startswith(version, "3.1")
        # NOP; the version should be in the format 3.1.x
    end
    @assert haskey(VERSIONS, version) "Version $(version) is not supported"

    openapi_schema = JSONSchema.Schema(JSON.parsefile(joinpath(SCHEMA_DIR , "$(VERSIONS[version]).json")))

    issue = JSONSchema.validate(spec, openapi_schema)
    if issue !== nothing
        throw(InvalidSwaggerSpecificationException(issue))
    end
end

function validate_spec(file::String)
    if endswith(file, ".json")
        return validate_spec(JSON.parsefile(file))
    end
    if endswith(file, ".yml")
        return validate_spec(YAML.load_file(file, dicttype=Dict{String, Any}))
    end
end

