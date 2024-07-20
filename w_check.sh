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

#touch $output_full
cp "$base_name" "$output_full" #Make a copy of the input file in the full edit directory
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
#Utility function which runs the given BRE sed command twice: once as given, and then once where case is ignored and the first character of the replacement string is capitalized. If the optional second argument contains 'd', the first parameter is instead treated as a BRE pattern, and the function builds a simple BRE sed command around it to replace it with the next character 1-4 spaces behind it. (Equivalent to running without ~"d" argument and with such a BRE sed command to delete the pattern in the first place)
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
#Shorthand to run the given sed command, in the current document, and with the option to try to preserve capitalization.
function insed () { #Argument 1: The sed command to run; Available flags: -P and -E to use PCRE or ERE, respectively (-B specifies BRE, which is redundant), -d or D to interpret Argument 1 as simply a pattern, and construct one of two sed commands to delete it (-d only deleted, and -D deletes by replacing with the first character up to 4 spacs later. -D is more likely, because of situations where you want to delete an entire word, and likely want to preserve capitalization). Assumes '/' as the delimiter 
	### Defaults
	re_mode='B' #By default, assume BRE sed
	to_build='N' #'N' for no build necessary, 'd' to build a delete command around the pattern, 'D' to build a command that replaces the given pattern with the next character up to four spaces later
	capital=false #Whether to double up the pattern to capitalize (performed last)

	###  Parse arguments
	local OPTIND OPTARG #Reset options flag index
	OPTSTRING=":dDPEBC"
	while getopts ${OPTSTRING} opt; do
		case ${opt} in 
			d) to_build='d';;# Take input as pattern, and simply delete
			D) to_build='D';;#Take input as pattern, and replace with next character up to 4 spaces away
			B) re_mode='B';; #BRE
			E) re_mode='E';; #ERE
			P) re_mode='P';; #PCRE		
			C) capital=true;; # Double up the sed command to capitalize the replacement
		esac
	done
	
	shift $((OPTIND - 1))
	###  The pattern to operate with
	pattern="$1"
	
	# Build a command if the input needs to be completed
	case ${to_build} in
		N) # No build neceessary
			;;
		d) # Build basic delete command 
			pattern="s/${pattern}//g"
			;;
		D) # Build delete command that actively finds a character up to 4 spaces later, and replaces the pattern with that (e.g. to allow capitalizing that character)
			if [[ "${re_mode}" =~ 'B' ]] ; then # Which characters to use to wrap depends on whether using BRE or ERE/PCRE, since escape behavior is reversed
				capstart='\('
				numstart='\{'
				capend='\)'
				numend='\}'
		       	else
		 		capstart='('
				numstart='{'
				capend=')'
				numend='}'
			fi		
			capsearch="\\${capstart}"
			caps=$(echo "$pattern" | grep -c "${capsearch}") #Count the number of capture groups already there
			((caps++)) #Go to the next available capture group
			pattern="s/${pattern}\\s${numstart}1,4${numend}${capstart}.${capend}/\\$caps/g"
			;;
	esac

	# Duplicate command to attempt to preserve capitalization
	if [ "$capital" == "true" ] ; then
		pattern="${pattern};$(echo "$pattern" | sed -e "s/\(.\)$/\1i/g" | sed -e "s/\//\/\\\u/2")" # In the copy of the pattern, append I to the string, and append \u to the second / (i.e. in front of the replacement) TODO: Now that this isn't stuck in a pipe, consider reworking this to properly try and capitalize the first letter of the pattern instead of just running for any capitalization
	fi

	
	# Run the final pattern, with the desired RE engine
	case ${re_mode} in
		B)sed -i -e "$pattern" "${output_full}";; #BRE
		E)sed -i -E -e "$pattern" "${output_full}";; #ERE
		P)perl -i -p -e "$pattern" "${output_full}";; #PCRE
	esac
}
#DEPRECATED: Similar to sedcap, but for the use case of removing a pattern or capture group of words regardless of capitalization. Runs a sed replace twice on the given pattern, once removing the pattern and up to three spaces afterwards, then again ignoring case and capitalizing the next character after the pattern. Intended to be run in a pipe, using BRE syntax.
#Example: "rmgroupcap 'very'" would replace "this is very good" with "this is good" and "end. Very often" with "end. Often"
function rmgroupcap_DEP () { #Argument 1: the pattern to delete; will delete the pattern and then delete it again without case and capitalize the next character; Argument 2: the next capture group number (e.g. the expression "\(happen\(ed|s\)\?\)" has two groups so 3 would be given
	#sed -e "s/$1//g" -e "s/$(echo "$1" | sed -e "s/\([(|]\)\(\\w\)/\1\\u\2/")\\b\(\\w\)/\$2/g"
	sed -e "s/$1\\s\{1,3\}//g" | sed -e "s/$1\\s\{1,3\}\(\\w\)/\\u\\$2/gI"
	
}

#Utility function and corresponding data which collects patterns to highlight. Highlighting is performed later by surrounding matches of such patterns with \colorbox{}{} from the LaTeX package xcolor #TODO: ensure xcolor is installed in the head LaTeX document when addding LaTeX traversal capability
to_highlight=() #List of patterns and colors to highlight; '%' alone precedes a color, as the program neither can nor should highlight LaTeX source code comments. '%#' precedes a mode specification, i.e. '%#E' signals that the following phrase uses ERE, or likewise '%#P' for PCRE. Such '%' specifiers only affect the next pattern, e.g., a pattern immediately after another pattern will be treated as BRE and highlighted in red
function hladd () { #Argument 1: The pattern to highlight; Options/flags: -c <color> specifies an xcolor color to use, -E specifies to use ERE, -P to use PCRE. -B to use BRE (redundant)
	if [ "$1" = "" ] ; then
		echo "Error: pattern to highlight must be specified"
	fi	
	local OPTIND OPTARG #Reset option flag counter
	OPSTRING=":c:PE" #Allow flags c with arg, P or E without
	while getopts ${OPTSTRING} opt; do
		case ${opt} in
			c) #Set the highlight
				to_highlight+=("%${OPTARG}")
				;;
			P) #Use PCRE instead of BRE
				to_highlight+=('%#P')
				;;
			E) #Use ERE insread of BRE
				to_highlight+=('%#E')
				;;
			:)
                                echo "Option -${OPTARG} requires an argument."
                                exit 1
                                ;;
                        ?)
                                echo "Invalid option: -${OPTARG}."
				exit 1
                                ;;
		esac
	done

	shift $(($OPTIND - 1))
	#Add pattern to list of patterns to highlight
       	to_highlight+=("$1")	
}
# Style guide & highlight colors: 
#  - red for things that should be removed, but can't automatically do so
#  - purple for likely passive voice (both in general but also stuff like "there are people who believe" instead of "some people believe"
#  - pink for things that should be removed, but can't reliably be identified
#  - brown for weird things that could use restructuring
#  - teal for things that are frequently misused (i.e large with something not about size, when with something not about time, words like code input output, verbs with data, or miscapitalization, or mistyping latin expressions)
delete='red'
passive='violet'
posdel='pink'
restruct='brown'
misuse='teal'

## Section 1: Reviewing Writing
	# 1a: Spell Checker (Out of scope)
	# 1b: Get rid of unnecessary propositional phrases -- author clearing throat
insed -C "s/it \(follows\|can be shown\|seems\|seems reasonable\|is evident\|is apparent\|happens\|occurs\) that[,]\?[ ]\+\(.\)/\2/g"
	# 1c: Get rid of there are/there is
hladd -c "$delete" "there is\|there are\|there exists\?\|there \(can\|may\) be"
	# 1d: Extraneous prepositions
sed "s/\(happen\|occur[r]\?\(ed\|s\)\?\) on \([^.,]*\(century\|decade\|year\|month\|week\|day\|hour\|minute\|second\)\)/\1 \3/gI" #Happens on a time 
sed "s/\(\(took\|take[sn]\?\) place\) on \([^.,]*\(century\|decade\|year\|month\|week\|day\|hour\|minute\|second\)\)/\1 \3/gI" #Takes place on a time, irregular construction
	# 1e: Get rid of passive voice constructions
# Initial word list is from Matt Might's shell scripts, not sure what licensing there is for compiled lists of words
irreg=$(cat "irregular_passive_verbs.txt")
hladd -c "$passive" "\\b\(am\|are\|were\|being\|is\|been\|was\|be\)\\b\(\\w\+\|\($irreg\)\)\\b"
	# 1f: Cite all images, methods, software, and empirical data (Out of scope)

## Section 2: Enhancing clarity
	# 2a: Be concise and direct (Out of Scope)
	# 2b: Using "very" suggest that a better word exists; replace it where possible
hladd "\\b[Vv]ery\\b"
	# 2c: Make sure that articles such as a, the, some, any, and each appear where necessary (Out of Scope: define where is necessary)
	# 2d: Ensure all subjects match the plurality of their verbs ("Apples is tasty" to "Apples are tasty") (Not Yet in Scope: define plurals)
	# 2e: Recover noun-ified verbs ('obtain estimates of' -> 'estimates')
hladd -c "$passive" "\(obtain\|provide\|secure\|allow\|enable\)\(s\|ed\)\?\( [^ .]*\)\{1,3\} \(of\|for\)"
	# 2f: Use the form <noun> <verb>ion over <verb>ion of <noun> (for example, convert "calculation of velocity" to "velocity calculation").
hladd -c "$passive" "[a-z]ion of\\b"
	# 2g: Reduce vague words like important or methodologic (TODO: I thought we implemented this)
	# 2h: Reduce acronyms/jargon
hladd -c "$misuse" " \([A-Z][a-z]\?\.\?\)\{2,\} " #TODO: decide how separate acronyms have to be from other words
	# 2i: Expand all acronyms on first use (Out of Scope: at most, would specially highlight the first one)
	# 2j: Turn negatives into positives (she was not often right -> she was usually wrong)
hladd -c "$passive" "\\bnot\\b"
	# 2k: Do not bury the verb, keep predicate close to subject at start of sentence (Out of Scope: Process and interpret grammar)
	# 2l: Refer to software consistently by name (TODO: Recognize and highlight generic references to 'the software')
	# 2m: Italicize unusual or unfamiliar words of phrases when you use them (OOS: Would require grammar/frequency processing)
	# 2n: If you use an uncommmon word, consider changing it or defining it in its first usage (OOS: grammar/frequency processing)

## Section 3: Enhancing Style
	# 3a: Vary your sentence structure to keep readers engaged (OOS: grammar processing)
	# 3b: Do not use contractions in technical writing
insed "s/I'm/I am/gI" 
insed -C "s/can't/can not/g"  
insed -C "s/won't/will not/g"  
insed -C "s/\(are\|is\|do\|should\|would\|could\|have\|had\|was\|were\)n't/\1 not/g" # [word]n't form contractions
insed -C "s/\(they\|you\|we\)'re/\1 are/gI" # [word]'re form contractions
insed -C "s/\(he\|she\|it\)'s/\1 is/gi" # [word]'s form contractions
	# 3c Use Punctuation to help you vary your sentence structure (OOS: Diagnostics)
	# 3d Follow the convention that the power to separate is (in order of increasing power): comma, colon, em dash, parentheses, semicolon, and period. (OOS: Diagnostics)
	# 3e In increasing order of formality: dash, parentheses, all others. Do not overdo the em dash and parentheses. (OOS: Diagnostics)
	# 3f Check that if there's a list in a sentence, it shouldn't come before the colon
hladd -c "$restruct" "\.[^,.;]\+\(\(,[^,.;:]\+\)\{3,\}\|\(;[,.;:]\+\)\{2,\}\):"
	# 3g Always use isotopic notation like '`$^{239}Pu$`. Never `$Pu-239$` or `$plutonium-239$`.'
insed "${atom_names_to_symbs}" # Should be noted using symbol, not name
insed ':repeat;s/^\(\([^$]*\$[^$]*\$\)\+[^$]*\)\([A-Z][a-z]\?[ -]\?[0-9]\{1,3\}\)/\1$\2#/g;t repeat' # Make sure isotopes are in math mode
insed "s/\(${atom_symbs}\)[ -]\([0-9]\{1,3\}\)/^{\2}\1/g" #Isotope upper left of symbol, not symbol-isotope
#sed 's/^\(\([^$]*\$[^$]*\$\)\+[^$]*\)\(\^{[0-9]\{1,3\}}${atom_symbs}\)/\1foo/g'
insed ':repeat;s/^\(\([^$]*\$[^$]*\$\)*[^$]*\)\(\^{[0-9]\{1,3\}}[ ]\?[A-Z][a-z]\)/\1$\3$/g;t repeat'  # Put any isotopic notation we just created into an equation environment
	# 3h: Strengthen your verbs (use sparingly: is, are, was, were, be, been, am) (Redundant: covered by 1e)
	# 3i: Only use 'large' when referring to size (TODO: improve with perl lookeaheads)
insed -c "$posdel" "large"
	# 3j: Do not use the word "when" unless referring to a time (try 'if' instead). (TODO: improve with perl lookaheads)
insed -c "$posdel" "when"
	# 3k: Clarify or change misused/overused words where necessary (e.g., code, input, output, different, value, amount, model). (OOS: Define list of misused or overused words)
	# 3l: Each sentence/paragraph should logically follow the previous sentence/paragraph. (OOS: Grammar/language processing)
	# 3m: Examples should use variables instead of numbers and symbolic math instead of acronyms (OOS: universally identifying such references)
	
## Section 4: Enhancing Grammar
	# 4a: "Data" is plural
insed "s/\(data\) is/\1 are/gI" 
insed "s/\(data\) was/\1 were/gI"  
insed -C "s/this \([^ ]\+\\b\)\?data/these \1data/g" #"this (room for a word, any more risks false positive) data
insed "s/\(data\)\( \\w\+ly\)\? \(suggest\|demonstrate\|include\|prove\)s/\1\2 \3/gI" #data + optional adverb + common verb in plural form
	# 4b: Compare to (point out similarities between different things) vs. compared with (point out differences between similar things) (OOS: grammar/language processing)
	# 4c: Elemental symbols (Ni, Li, Na, Pu) are capitalized, but their names are not (nickel, lithium, sodium, plutonium).
insed "s/ \(${atom_symbs}\)\([ -]\)/ \\u\1\2/gI"  
insed "s/\([^.]\{4\}\)\(${atom_names}\)/\1\\l\2/gI" #Detect end of sentence by presence of a period
	# 4d: Do not use the word "where" unless referring to a location (try "such that," or "in which").
hladd -c "$posdel" "where" # TODO: improve with lookaheads
	# 4e: Avoid run-on sentences
clauselen=75 #Things over this many characters are assumed to be full clauses and not just items in a list (or if it is, a list that could use refactoring)
hladd -c "$restruct" "\.\([^.]\{$clauselen,\}[,;]\)\{3,\}[^.]*\." #More than 4 large clause sections in the same sentence
maxsenlen=450 #Maximum recommended sentence length 
hladd -c "$restruct" "\.[^.]\{$maxsenlen\}\." #Sheer character length
	# 4f: The preposition "of" shows belonging, relations, or references. The preposition "for" shows purpose, destination, amount, or recipients. They are not interchangeable. (OOS: grammar/language processing)
	
## Section 5: Enhancing punctuation
	# 5a:  Commas and periods go inside end quotes, except when there is a parenthetical reference afterward.
insed "s/\",/,\"/g" 
insed "s/,\"\(\\b\?\\\cite{[^{}]}\)/\"\1,/g" 
	# 5b: colons and semicolons go outside end quotes
insed "s/\([;:]\)\"/\"\1/g"
	# 5c: A semicolon connects two independent clauses OR separates items when the list contains internal punctuation. (OOS: grammar processing)
	# 5d: Use a colon to introduce a list, quote, explanation, conclusion, or amplification. (OOS: identifying lists reliably TODO: if they can be identified, move this to highlight)
	# 5e: The Oxford comma must appear in lists (e.g., "lions, tigers, and bears").
insed "s/\(\(,[^.,;]\+\)\{2,\}\) and/\1, and/g" #TODO: should this be left to highlighting
	# 5f: Use hyphens to join words acting as a single adjective before a noun (e.g., "well-known prankster"), not after a noun (e.g., "the prankster is well known"). (OOS: grammar provessing)
	# 5g: Two words joined by a hyphen in title case should both be capitalized.
hladd -c "$misuse" "[A-Z][a-zA-Z0-9]*-[a-zA-Z0-9]*"
	# 5h: Hyphens join a prefix to a capitalized word, figure, or letter (e.g., pre-COVID, T-cell receptor, post-1800s); compound numbers (e.g., sixty-six); words to the prefixes ex, self, and all (e.g., ex-sitter, self-made, all-knowing); and words to the suffix elect (e.g., president-elect).
insed "s/\(pre\|post\) \([A-Z0-9]\)/\1-\2/g" # prefixes to capitalized words, figures, letters
#insed "s/\(\\b[A-Za-z]\) \(\)"	 # Letters as prefixes (e.g. T-Cell) TODO: work out avoidance of regular letters like a, I, while still being broad enough to work
insed "s/\(twenty\|thirty\|forty\|fifty\|sixty\|seventy\|eighty\|ninety\) \(one\|two\|three\|four\|five\|six\|seven\|eight\|nine\)/\1-\2/g" # Compound numbers from 21 to 99
insed "s/\(self\|all\|ex\) \(\\w\+\\b\)/\1-\2/g" # All words to prefixes ex self all  
insed "s/\(\\b\\w\+\) elect/\1-elect/g" # Words to suffix -elect

## Section 6: Using Latin
	# 6a: The Latin abbreviations viz., i.e., and e.g. should all have commas before and after them (e.g., "We can classify a large star as a red giant, e.g., Stephenson 2-18").
insed "s/,\?\(viz\.\|i\.e\.\|i\.e\.\),\?/,\1,/g" 
	# 6b: The Latin abbreviations cf., et al., or q.v. should not automatically have commas after them.
hladd -c "$posdel" "\(cf\|et al\|q\.v\)\.,"
	# 6c: Versus should always have a period (at least in American English)
insed "s/vs[^\.]/vs./g"
	# 6d: "and etc." is redundant since etc. stands for *et* cetera
insed "s/and etc\./etc\./g" 
	# 6e: "et" in abbreviations should not have a period, since et is a whole word
insed "s/ et\./ et/g" #This SHOULD be fine, since I can't think of when you would end a sentence with et
	# 6f: Some abbreviations, such as N.B., require capitalization | 
to_cap=('N\.B\.' 'CV') #TODO: add any more of these, this could include lowercase 
for tc in ${to_cap[@]}; do 
	insed "s/$tc/$tc/gI" 
done
	# 6g: full latin phrases other than et should generally be italicized
if [ "$hasperl" = true ]; then #TODO: Handle using or not using perl
	insed -P 's/(?<!\{\s{1,5})(in (situ|vivo|vitro)|ab initio)(?!\s+\})/\\emph\{\1\}/g'
fi
	
## Section 7: Tables and Figures: TODO: Add using more sophisticated behavior than stream editing
	# 7a: The text should refer to all tables and figures. 
	# 7b: When referring to figures by their number, use `Figure 1` and `Table 1.` They should be capitalized and not abbreviated (not `fig. 1` or `figure 1`).
	# 7c: Align all columns of numbers in tables such that the decimals line up.
	# 7d All values should probably have the same number of significant digits in a single column.
	# 7e Give units for each numerical column.
	# 7f A table should have only three horizontal lines (no vertical lines and no more than three).

## Section 8: Enhancing Math
	# 8a: Define all variables with units. If unitless, indicate this is the case `$[-]$`. (OOS: universally identifying variables)
	# 8b: Subscripts should be brief and can be avoided with common notation. For example, `$\dot{m}$` is better than `$m_f$` which is superior to `$m_{flow}$`.
hladd -c "$restruct" "_{[^{}]}" 
	# 8c: Variable names should be symbols rather than words `m` is better than `mass` and `\ksi` is better than `one_time_use_variable`. (OOS: identifying words that are variables)
	# 8d: The notation `$3.0\times10^{12}$` is preferred over `$3e12$`.
insed "s/\([0-9]\)e\([0-9]\+\)/\1\\\times10\^{\2}/g" 
	# 8e: Equations should be part of a sentence.
sed -e "s/\(\\\begin{\(equation\|align\|gather\|multiline\)[*]\+}\)\(*\)\(\\\end{\2\)/\1\\\colorbox{$hl_color}{\$\\\displaystyle \3\$}\4/g" -i ${to_highlight} #Special highlight needed to respect math environment; this highlights equations which come right after a period
	# 8f: Equations should be in the `align` environment. Align them at the `=` sign.
sed -e "s/\(\.[!.]*\.\)\(\\b\\\begin{\(equation\|align\|gather\|multiline\)[*]\+}\)\(*\)\(\\\end{\3\)/\\\colorbox{$hl_color}{\1}\2\\\colorbox{$hl_color}{\$\\\displaystyle \4\$}\5/g" -i ${to_highlight} #Special highlight needed to respect math environment; this highlights equations which come right after a period
	# 8g: Variables should be defined in the 'align' environment, not buried in paragraphs (OOS: identifying variables)



# Stream input from file
cat $1 |
# Part 1: Execute tweaks which can be automatically performed 

	# 1a: clearing throat by prepending "it seems like" 
	# 1b: unnecessary prepositions for saying something happened at a time
	# Same thing but for "took/takes place", an irregular construction
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

hl_color='red' #Red by default
mode='B' #BRE by default
#Iterate through each highlight instruction
for instr in "${to_highlight[@]}"
do
	if [ "$instr" =~ '^%'] ; then #Some kind of special isntruction like color or mode
		if [ "$instr" =~ '^%#'] ; then #Specifically a mode instructor
			mode="${instr#'%#'}"
		else #Otherwise, a color instruction
			hl_color="${instr#'%'}"
		fi
	else # If not a special instruction, then the pattern to highlight
		case "${mode}" in
			[bB]) #BRE
				sed -i "s/\($1\)/\\\colorbox{$hl_color}{\1}/g$2" "$to_highlight"
				;;
			[pP]) #PCRE
				perl -i -pe "s/($1)/\\\colorbox\{$hl_color\}\{\1\}/g$2" "$to_highlight"
				;;
			[eE]) #ERE
				sed -iE "s/($1)/\\\colorbox\{$hl_color\}\{\1\}/g$2" "$to_highlight"
				;;
		esac
		#Reset to default color and mode
		hl_color='red'
		mode='B'
	fi	
done


#TODO: Do we want to provide command line summaries? E.g. how many different instances of punctuation were used, average sentence length, commonly used words?



exit
