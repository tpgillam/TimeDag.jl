using TimeDag
using Documenter

DocMeta.setdocmeta!(TimeDag, :DocTestSetup, :(using TimeDag); recursive=true)

makedocs(;
    modules=[TimeDag],
    authors="Invenia Technical Computing Corporation",
    repo="https://github.com/invenia/TimeDag.jl/blob/{commit}{path}#{line}",
    sitename="TimeDag.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://invenia.github.io/TimeDag.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
    checkdocs=:exports,
    strict=true,
)

deploydocs(;
    repo="github.com/invenia/TimeDag.jl",
)
