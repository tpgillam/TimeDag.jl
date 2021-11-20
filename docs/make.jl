using Documenter
using Statistics
using TimeDag

DocMeta.setdocmeta!(TimeDag, :DocTestSetup, :(using TimeDag); recursive=true)

# This is inspired by the following, to prevent a `gksqt` process blocking (and needing
# manual termination) for every plot when generating documentation on MacOS.
# https://discourse.julialang.org/t/deactivate-plot-display-to-avoid-need-for-x-server/19359/2
# Another choice could be "100":
# https://discourse.julialang.org/t/generation-of-documentation-fails-qt-qpa-xcb-could-not-connect-to-display/60988
# Empirically, both choices seem to work.
withenv("GKSwstype" => "nul") do
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
            "concepts.md",
            "examples.md",
            "Reference" => [
                "reference/fundamentals.md",
                "Node ops" => [
                    "reference/align.md",
                    "reference/arithmetic.md",
                    "reference/online_windowed.md",
                    "reference/misc_ops.md",
                    "reference/sources.md",
                ],
                "reference/creating_ops.md",
                "reference/internals.md",
            ],
        ],
        checkdocs=:exports,
        strict=true,
    )
end

deploydocs(; repo="github.com/invenia/TimeDag.jl", devbranch="main")
