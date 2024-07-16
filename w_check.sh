#!/bin/bash

# Ensure file was provided
if [ "$1" = "" ]; then
 echo "usage: `basename $0` <file> ..."
 exit
fi

# Check if perl is installed; this only affects a couple of things that use lookaheads
hasperl=false
if perl < /dev/null > /dev/null 2>&1  ; then
      hasperl=true
fi
if [ "$hasperl" = false ] ; then
	echo "Perl not found; some features limited"
fi

# Parse base file name
base_name=$(echo $1 | sed s/"\.tex$"//g)
echo "$base_name"

# Identify output file names, one for the full edits and highlighted suggestions, and one for the latexdiff of the direct edits
output_full="output/${base_name}_edit.tex"
output_diff="output/${base_name}_diff.tex"

touch $output_full
touch $output_diff

# Define utility data

# Elemental data
elemcsv="elements.csv"
atom_symbs=$(awk -F ',' '{if (NR>1) {print $3,"\\|"}}' $elemcsv | tr -d '\n' | tr -d ' ' | sed s/..$//g)
atom_names=$(awk -F ',' '{if (NR>1) {print $2,"\\|"}}' $elemcsv | tr -d '\n' | tr -d ' ' | sed s/..$//g)
atom_names_to_symbs="$(awk -F ',' '{if (NR<5) {print ";s/",$2,"\\([ -][0-9]\\)/",$3,"\\1/gI"}}' elements.csv | tr -d ' ' | sed "s/-e/ -e /g" | sed "s/\[-/\[ -/g" | tr -d "\n" | sed 's/$/\n/')" #Replace with one single sed argument (NOTE: this is insecure)

#DEPRECATED: Utility function to run the given (simple and starting with a letter) sed command twice: once as presented, and once where the first character of the pattern and the first character of the replacement have been capitalized. Intended to be run in a pipe, using BRE syntax.
#Example: "sedcap 's/they're/they are/g' | " would be equivalent to running "sed 's/they're/they are/g' | sed 's/They're/They are/g'"
function sedcap_DEP () {
	sed -e "$1" -e "$(echo "$1" | sed -e "s/\/\(.\)/\/\u\1/1" | sed -e "s/\//\/\\\u/2")"
}
#Utility function which runs the given BRE sed command twice: once as given, and then once where case is ignored and the first character of the replacement string is highlighted. If the optional second argument contains 'd', the first parameter is instead treated as a BRE pattern, and the function builds a simple BRE sed command around it to replace it with the next character 1-4 spaces behind it. (Equivalent to running without ~"d" argument and with such a BRE sed command to delete the pattern in the first place)
function sedcap () { #Argument 1: either a complete BRE sed command, or a BRE pattern in a mode such as 'd'; Argument 2 (optional, default 'none'): Flags to use for editing. Currently, if a 'd' is in this string, for example, the pattern is treated as only a BRE pattern, and wrapped in a basic sed command to replace that pattern with the first character up to three spaces afterwards.
	pattern="$1"
	mode="${2:-'none'}"
	if [[ "$mode" =~ "[dD]" ]]; then
		caps=$(echo $pattern | grep -c "\\\(") #Count the number of capture groups already there
		((caps++)) #Go to the next available capture group
		pattern="s/${pattern}\\s\{1,4\}\(.\)/\\$caps/g"
	fi
	sed -e "$pattern" -e "$(echo "$pattern" | sed -e "s/\(.\)$/\1I/g" | sed -e "s/\//\/\\\u/2")"
}

#DEPRECATED: Similar to sedcap, but for the use case of removing a pattern or capture group of words regardless of capitalization. Runs a sed replace twice on the given pattern, once removing the pattern and up to three spaces afterwards, then again ignoring case and capitalizing the next character after the pattern. Intended to be run in a pipe, using BRE syntax.
#Example: "rmgroupcap 'very'" would replace "this is very good" with "this is good" and "end. Very often" with "end. Often"
function rmgroupcap_DEP () { #Argument 1: the pattern to delete; will delete the pattern and then delete it again without case and capitalize the next character; Argument 2: the next capture group number (e.g. the expression "\(happen\(ed|s\)\?\)" has two groups so 3 would be given
	#sed -e "s/$1//g" -e "s/$(echo "$1" | sed -e "s/\([(|]\)\(\\w\)/\1\\u\2/")\\b\(\\w\)/\$2/g"
	sed -e "s/$1\\s\{1,3\}//g" | sed -e "s/$1\\s\{1,3\}\(\\w\)/\\u\\$2/gI"
	
}

# Stream input from file
cat $1 |
# Part 1: Execute tweaks which can be automatically performed 

	# 1a: clearing throat by prepending "it seems like" 
sedcap "s/it \(follows\|can be shown\|seems\|seems reasonable\|is evident\|is apparent\|happens\|occurs\) that[,]\?[ ]\+\(.\)/\2/g" |
	# 1b: unnecessary prepositions for saying something happened at a time
sed "s/\(happen\|occur[r]\?\(ed\|s\)\?\) on \([^.,]*\(century\|decade\|year\|month\|week\|day\|hour\|minute\|second\)\)/\1 \3/gI" | 
	# Same thing but for "took/takes place", an irregular construction
sed "s/\(\(took\|take[sn]\?\) place\) on \([^.,]*\(century\|decade\|year\|month\|week\|day\|hour\|minute\|second\)\)/\1 \3/gI" | 
	# 1c: duplicate words
sed "s/\\b\(\\w\+\)\\s\+\1\\b/\1/g" |
	# 1d: Muddling words like "quite, various, a number of" that don't really clarify anything
sedcap "\(various\|a number of\|many\|quite\|a few\|methodologic\(al\)\?\|important\)" "d" | 
	# 1e: Improper isotopic notation
sed "${atom_names_to_symbs}" | # Should be noted using symbol, not name
sed ':repeat;s/^\(\([^$]*\$[^$]*\$\)\+[^$]*\)\([A-Z][a-z]\?[ -]\?[0-9]\{1,3\}\)/\1$\2#/g;t repeat' | # Make sure isotopes are in math mode
sed "s/\(${atom_symbs}\)[ -]\([0-9]\{1,3\}\)/^{\2}\1/g" | #Isotope upper left of symbol, not symbol-isotope
#sed 's/^\(\([^$]*\$[^$]*\$\)\+[^$]*\)\(\^{[0-9]\{1,3\}}${atom_symbs}\)/\1foo/g'
sed ':repeat;s/^\(\([^$]*\$[^$]*\$\)*[^$]*\)\(\^{[0-9]\{1,3\}}[ ]\?[A-Z][a-z]\)/\1$\3$/g;t repeat' | # Put any isotopic notation we just created into an equation environment
	# 1f: Atomic symbols should be capitalized (Na not na)
sed "s/ \(${atom_symbs}\)\([ -]\)/ \\u\1\2/gI" | 
	# 1g: Atomic names should not, unless they are at the start of a sentence
sed "s/\([^.]\{4\}\)\(${atom_names}\)/\1\\l\2/gI" | #Detect end of sentence by presence of a period
	# 1h: Common number issues with "data"/"datum"
sed "s/\(data\) is/\1 are/gI" | 
sed "s/\(data\) was/\1 were/gI" | 
sedcap "s/this \([^ ]\+\\b\)\?data/these \1data/g" | #"this (room for a word, any more risks false positive) data
sed "s/\(data\)\( \\w\+ly\)\? \(suggest\|demonstrate\|include\|prove\)s/\1\2 \3/gI" | #data + optional adverb + common verb in plural form
	# 1i: commas should go inside end quotes
sed "s/\",/,\"/g" | 
	# 1j: except when there's a citation
sed "s/,\"\(\\b\?\\\cite{[^{}]}\)/\"\1,/g" | 
	# 1k: colons and semicolons go inside end quotes
sed "s/\([;:]\)\"/\"\1/g" | 
	# 1l: And then standard punctuation goes after the citaiton 
sed "s/\"\([.;:?!]\)\(\\b\?\\\cite{[^{}]}\)/\"\2\1/g" | 
	# 1m: Oxford comma (last item in comma separated list without comma before the and)
sed "s/\(\(,[^.,;]\+\)\{2,\}\) and/\1, and/g" | #TODO: should this be left to highlighting
	# 1n: Scientific notation should be in *10^whatever instead of ewhatever
sed "s/\([0-9]\)e\([0-9]\+\)/\1\\\times10\^{\2}/g" |
	# 1o: Hyphens should join some prefixes to capitalized words/letters/figures, compound numbers, all words to prefixes ex self all, and the suffix elect
sed "s/\(pre\|post\) \([A-Z0-9]\)/\1-\2/g" | # prefixes to capitalized words, figures, letters
#sed "s/\(\\b[A-Za-z]\) \(\)"	| # Letters as prefixes (e.g. T-Cell) TODO: work out avoidance of regular letters like a, I, while still being broad enough to work
sed "s/\(twenty\|thirty\|forty\|fifty\|sixty\|seventy\|eighty\|ninety\) \(one\|two\|three\|four\|five\|six\|seven\|eight\|nine\)/\1-\2/g" | # Compound numbers from 21 to 99
sed "s/\(self\|all\|ex\) \(\\w\+\\b\)/\1-\2/g" | # All words to prefixes ex self all  
sed "s/\(\\b\\w\+\) elect/\1-elect/g" | # Words to suffix -elect
	# 1p: Contractions should be avoided in technical writing
sed "s/I'm/I am/gI" |
sedcap "s/can't/can not/g" | 
sedcap "s/won't/will not/g" | 
sed "s/\(are\|is\|do\|should\|would\|could\|have\|had\|was\|were\)n't/\1 not/gI" | # [word]n't form contractions
sed "s/\(they\|you\|we\)'re/\1 are/gI" | # [word]'re form contractions
sed "s/\(he\|she\|it\)'s/\1 is/gi" | # [word]'s form contractions
	# 1q: Misspelled Latin abbreviations
#sed 's/ eg\.\? / e\.g\. /g' | # e.g. needs both periods TODO: decide how necessary this is (i.e. spellcheckers exist), and add more
	# 1r: Latin abbreviations viz., i.e., and e.g. should be preceded and followed by commas
sed "s/,\?\(viz\.\|i\.e\.\|i\.e\.\),\?/,\1,/g" |
	# 1s: Versus should always have a period (at least in American English)
sed "s/vs[^\.]/vs./g" | 
	# 1t: "and etc." is redundant since etc. stands for *et* cetera
sed "s/and etc\./etc\./g" | 
	# 1u: "et" in abbreviations should not have a period, since et is a whole word
sed "s/ et\./ et/g" | #This SHOULD be fine, since I can't think of when you would end a sentence with et
	# 1v: Some abbreviations, such as N.B., require capitalization | 
to_cap=('N\.B\.' 'CV') #TODO: add any more of these, this could include lowercase 
{for tc in ${to_cap[@]}; do #TODO: figure out how to get a loop working in a pipe, or refactor this entirely to not use pipes (such as with -i)
	sed "s/$tc/$tc/gI" |
done}
	# 1w: full latin phrases other than et should generally be capitalized
if [ "$hasperl" = true ]; then
	perl -pe 's/(?<!\{\s+)(in (situ|vivo|vitro)|ab initio)(?!\s+\})/\\emph\{\1\}/g' |
fi
	#
	

#Send final stream to full edit file file
cat > $output_full

#Run latexdiff to generate a new copy which demonstrates the changes actively made
latexdiff "$1" "$output_full" > "$output_diff"


# Part 2: Load either latexdiff or base edit file, then add highlights for suggestions which can't be automatically performed (e.g. it could identify that you use a word a lot, but it would be foolish for it to automatically thesaurus these words, that's for the writer to decide)

to_highlight="$output_full" # Currently runs on the full output file, but we should be able to change this
#echo "now highlighting: $to_highlight"
# Parameter: the pattern to match
hl_color="red" #Default highlight color: red
function highlight () { #highlight a pattern with color, and write result back to file. Param 1: the pattern to highlight, Param 2: any flags to add after the g
	sed -i "s/\($1\)/\\\colorbox{$hl_color}{\1}/g$2" "$to_highlight"
}

function perl_hili () { #Similar to highlight but using perl to enable lookarounds n such
	perl -i -pe "s/($1)/\\\colorbox\{$hl_color\}\{\1\}/g$2" "$to_highlight"
}

# Initial word list is from Matt Might's shell scripts, not sure what licensing there is for compiled lists of words
irreg=$(cat "irregular_passive_verbs.txt")
# Style guide & highlight colors: 
#  - red for things that should be removed, but can't automatically do so
#  - purple for likely passive voice (both in general but also stuff like "there are people who believe" instead of "some people believe"
#  - pink for things that should be removed, but can't reliably be identified
#  - brown for weird things that could use restructuring
#  - teal for things that are frequently misused (i.e large with something not about size, when with something not about time, words like code input output, verbs with data, or miscapitalization, or mistyping latin expressions)

# w
hl_color="red"
highlight "[a-z]ion of\\b"
highlight "\\b[Vv]ery\\b"
highlight "\\bnot\\b"
# Need to test this more: it is designed to match verb + 1-3 words + of/for, and seems to work but still seems risky
highlight "\(obtain\|provide\|secure\|allow\|enable\)\(s\|ed\)\?\( [^ .]*\)\{1,3\} \(of\|for\)"

hl_color="pink"
#Only use "large" to refer to size
highlight "large"
#Only use "when" to refer to time, not for hypotheticals (try "if" instead)
highlight "when"
#Be careful using acronyms, to expand them the first time (TODO: list of common enough acronyms to ignore)
highlight " \([A-Z][a-z]\?\.\?\)\{2,\} " #TODO: decide how separate acronyms have to be from other words
#The Latin abbreviations cf., et al., and q.v. should not automatically have commas after them
highlight "\(cf\|et al\|q\.v\)\.,"

if [ "$hasperl" = true ] ; then
fi

hl_color="violet"
highlight "there is\|there are\|there exists\?\|there \(can\|may\) be" "I"
#passive and some weakened verbs
highlight "\\b\(am\|are\|were\|being\|is\|been\|was\|be\)\\b\(\\w\+\|\($irreg\)\)\\b"

hl_color="brown"
#lists separated by commas or semicolons which come before a comma in a sentence
highlight "\.[^,.;]\+\(\(,[^,.;:]\+\)\{3,\}\|\(;[,.;:]\+\)\{2,\}\):"
#Improper elemental notation, but with name so not easily mapped yet
highlight "\(${atom_names}\)[ -][0-9]\{1,3\}"
clauselen=75 #Things over this many characters are assumed to be full clauses and not just items in a list (or if it is, a list that could use refactoring)
#Run on sentences: more than 4 large clause sections in the same sentence
highlight "\.\([^.]\{$clauselen,\}[,;]\)\{3,\}[^.]*\."
maxsenlen=450 #Maximum recommended sentence length 
#Run on sentence: sheer character length (edit this to use lookaheads and avoid tables n stuff)
highlight "\.[^.]\{$maxsenlen\}\."
#Long subscripts
highlight "_{[^{}]}" #Reminder that this is a BRE script :)
#Equations should use align environment, not multiline/group
sed -e "s/\(\\\begin{\(equation\|align\|gather\|multiline\)[*]\+}\)\(*\)\(\\\end{\2\)/\1\\\colorbox{$hl_color}{\$\\\displaystyle \3\$}\4/g" -i ${to_highlight} #Special highlight needed to respect math environment; this highlights equations which come right after a period
#Equations should be integrated into sentences, not floating on their own
sed -e "s/\(\.[!.]*\.\)\(\\b\\\begin{\(equation\|align\|gather\|multiline\)[*]\+}\)\(*\)\(\\\end{\3\)/\\\colorbox{$hl_color}{\1}\2\\\colorbox{$hl_color}{\$\\\displaystyle \4\$}\5/g" -i ${to_highlight} #Special highlight needed to respect math environment; this highlights equations which come right after a period



hl_color="teal"
#Title case hyphens: hyphen pairs where the first character is capitalized
highlight "[A-Z][a-zA-Z0-9]*-[a-zA-Z0-9]*"

#TODO: Do we want to provide command line summaries? E.g. how many different instances of punctuation were used, average sentence length, commonly used words?
exit
