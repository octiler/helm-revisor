#!/usr/bin/env bash
set -e

function err () {
    [[ 0 -lt $1 ]] && errcode=$1 && shift || errcode=127
    echo $@ >&2 && exit $errcode
}

[[ "true" == `git rev-parse --is-inside-work-tree` ]] || err 120 not in a git repository
[[ "--classified" == "$1" ]] && cat && exit 0
cd `git rev-parse --show-toplevel`/classified || err 120 cannot find classified path in this git repository
[[ $# -eq 1 ]] && SENSITIVE=$1 || SENSITIVES=(`find . -maxdepth 1 -mindepth 1 -type d -not -name mock -exec basename {} \;`)
[[ 1 -eq ${#SENSITIVES[@]} ]] && SENSITIVE=${SENSITIVES[0]}
[[ ${#SENSITIVE} -gt 0 ]] || err 120 cannot locate sensitive data
[[ -d ${SENSITIVE} ]] && cd ${SENSITIVE} || err 120 ${SENSITIVE} is not a directory existed

## Refs: https://github.com/google/re2/wiki/Syntax
# ------------------------------------------------------------------------------------------------------------------------------
function preprocess () {
    yq '(.. | select(tag == "!!str" and test("^<\|.*[[:alnum:]./_-]+@.*\|>$"))) |= (. as $item|
            capture("^<\|(?<prefix>.*?)(?<keyset>[[:alnum:]./_-]+)@(?<keypath>[[:alnum:]._]*)(?<suffix>.*?)\|>$") as $match
            |$match|[
                        "<|",
                        .prefix,
                        "load(\"",
                        .keyset,
                        "\")",
                        .keypath
                            |sub("^([[:alnum:]._])", "|.${1}"),
                        .suffix,
                        "|>"
                    ]|join("")
        )
    ' $@
}

preprocessing=`preprocess -`
preprocessed=`echo "$preprocessing" | preprocess -`

until [[ "$preprocessing" == "$preprocessed" ]];do
    preprocessing="$preprocessed"
    preprocessed=`echo "$preprocessing" | preprocess -`
done

# matches=(`echo "$preprocessed" | grep -oP "^<\|.*[\w.-_]+@.*\|>$" || true`)
matches=(`echo "$preprocessed" | grep -oE "^<\|.*[[:alnum:]./_-]+@.*\|>$" || true`)
[[ ${#matches[@]} -eq 0 ]] || err 121 cannot preprocess the pattern followed: ${matches[0]}

# ------------------------------------------------------------------------------------------------------------------------------
function parse () {
    yq '(.. | select(tag == "!!str" and test("^<\|.*\|>$"))) |= (. as $item|
            capture("^<\|(?<expression>.*)\|>$") as $match
            |$match|eval(.expression)
        )
    ' $@
}

parsing=`echo "$preprocessed" | parse -`
parsed=`echo "$parsing" | parse -`

until [[ "$parsing" == "$parsed" ]];do
    parsing="$parsed"
    parsed=`echo "$parsing" | parse -`
done

# matches=(`echo "$parsed" | grep -oP "^<\|.*\|>$" || true`)
matches=(`echo "$parsed" | grep -oE "^<\|.*\|>$" || true`)
[[ ${#matches[@]} -eq 0 ]] || err 121 cannot parse the pattern followed: ${matches[0]}

# ------------------------------------------------------------------------------------------------------------------------------
function unveil () {
    yq '(.. | select(tag == "!!str" and test("[[:alnum:]./_-]+@[[:alnum:]._-]*([[:space:]]*\|[^|~]*)*~>"))) |= (. as $item|
            capture("<~(?<keyset>[[:alnum:]./_-]+)@(?<keypath>[[:alnum:]._-]*)(?<keyprocessor>([[:space:]]*\|[^|~]*)*)~>") as $match
            |$item|sub(
                $match|["<~",.keyset,"@",.keypath,.keyprocessor,"~>"]|join("")
                    |sub("\\\\","\\\\")
                    |sub("\"","\\\"")
                    |sub("\\(","\\(")
                    |sub("\\)","\\)")
                    |sub("\[","\[")
                    |sub("\]","\]")
                    |sub("\|","\|")
                    |sub("\+","\+")
                    |sub("\*","\*")
                    |sub("\.","\.")
                    |sub("\?","\?")
                    |sub("\^","\^")
                    |sub("\$","\$")
                ,load($match.keyset)|eval("." + $match.keypath)|eval("." + $match.keyprocessor)
            )
        )
    ' $@
}

unveiling=`echo "$parsed" | unveil -`
unveiled=`echo "$unveiling" | unveil -`

until [[ "$unveiling" == "$unveiled" ]];do
    unveiling="$unveiled"
    unveiled=`echo "$unveiling" | unveil -`
done

# matches=(`echo "$unveiled" | grep -oP "<~[\w.-_]+@[\w.-_]*(\s*\|[^|~]*)*~>" || true`)
matches=(`echo "$unveiled" | grep -oE "<~[[:alnum:]./_-]+@[[:alnum:]._-]*([[:space:]]*\|[^|~]*)*~>" || true`)
[[ ${#matches[@]} -eq 0 ]] || err 122 cannot unveil the pattern followed: ${matches[0]}

# ------------------------------------------------------------------------------------------------------------------------------
echo "$unveiled"
