#!/bin/bash

# Ensure file was provided
#if [ "$1" = "" ]; then
# echo "usage: `basename $0` <file> ..."
# exit
#fi

# Check if perl is installed; this only affects a couple of things that use lookaheads
hasperl=false
if perl < /dev/null > /dev/null 2>&1  ; then
      hasperl=true
fi
if [ "$hasperl" = false ] ; then
	echo "Perl not found; some features limited"
fi

# Parse base file name
#base_name=$(echo $1 | sed s/"\.tex$"//g)
#echo "$base_name"

# Handle edits on a directory by directory basis. Files in the input directory will be copied to mirroring file locations in the directories output/edit and output/diff

if [ ! "$1" == "" ]; then #If a filepath is specified, use that filepath instead
	input_dir=$(echo "$1" | sed 's%\([^/]\)$%\1/%') #Ensure a / at the end
	edit_dir=$(echo "$input_dir" | sed 's%/$%_output/edit/%') #Use <path>_output instead of output
	diff_dir=$(echo "$input_dir" | sed 's%/$%_output/diff/%') 
	echo "Copying from '$input_dir' to '$edit_dir' and '$diff_dir'"
else #But by default, look for an "input" directory
	input_dir="input/" #Prefix for files which will be edited
	edit_dir="output/edit/" #Prefix for the fully edited files
	diff_dir="output/diff/" #Prefix for the files showing the changes and suggestions 
	echo "No input directory specified, copying from '$input_dir' to '$edit_dir' and '$diff_dir'"
fi

# ensure the directories exist
mkdir -p "$edit_dir" 
mkdir -p "$diff_dir"


# Identify output file names, one for the full edits and highlighted suggestions, and one for the latexdiff of the direct edits
#output_full="output/${base_name}_edit.tex"
#output_diff="output/${base_name}_diff.tex"

#touch $output_full
echo "$edit_dir$(basename fingu/notresults.tex)"
#find "$input_dir" -type f -exec sh -c 'echo ${edit_dir}$(echo $input_dir)' \; 
files=$(find "$input_dir" -type f -exec echo {} \; | grep -v "Zone\.Identifier$" | sed "s%^$input_dir%%g")
#echo "$texfiles"
OIFS="$IFS"
#while IFS=$'\n' read -ra FILES <<< "$texfiles"; do
#	for file in "${FILES[@]}" ; do
#		cp "${input_dir}${file}" "${edit_dir}${file}"
#		echo "test hihi$file"
#	done	
#done
#New approach that uses a loop inside the exec command in a way that might possibly solve this issue Update: this has the same expansion problem
#find "$input_dir" -type f -exec sh -c '
#	for file do
#		echo "$file" | sed "s%^${input_dir}%%"
#		echo \"$input_dir\"
#	done
#' exec-sh {} +

#Third approach:
while IFS= read -r line; do 
	# Each line is a file address from the input dir
	
	# If it has its own new directories, create those as necessary
	subdir=$(dirname "$line")
	#echo "$subdir"
	if [ "$subdir" != "" ] ; then
		mkdir -p "$edit_dir$subdir"
	fi

	touch "$edit_dir$line"
	cp "$input_dir$line" "$edit_dir$line"
done <<< "$files"

echo "just checked directory"

# Define utility functions

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
		
	echo "final pattern: $pattern"	
	# Run the final pattern, with the desired RE engine, across the full edit directory TODO: 
	case ${re_mode} in
		B)find "$edit_dir" -type f -name "*.tex" -exec sed -i -e "$pattern" {} \; ;; #BRE
		E)find "$edit_dir" -type f -name "*.tex" -exec sed -i -E -e "$pattern" {} \; ;; #ERE
		P)find "$edit_dir" -type f -name "*.tex" -exec perl -i -p -e "$pattern" {} \; ;; #PCRE
	esac
}

#Utility function and corresponding data which collects patterns to highlight. Highlighting is performed later by surrounding matches of such patterns with \colorbox{}{} from the LaTeX package xcolor #TODO: ensure xcolor is installed in the head LaTeX document when addding LaTeX traversal capability
to_highlight=() #List of patterns and colors to highlight; '%' alone precedes a color, as the program neither can nor should highlight LaTeX source code comments. '%#' precedes a mode specification, i.e. '%#E' signals that the following phrase uses ERE, or likewise '%#P' for PCRE. Such '%' specifiers only affect the next pattern, e.g., a pattern immediately after another pattern will be treated as BRE and highlighted in red
function hladd () { #Argument 1: The pattern to highlight, Argument 2 (optional): The note to add about the highlight; Options/flags: -c <color> specifies an xcolor color to use, -E specifies to use ERE, -P to use PCRE. -B to use BRE (redundant)
	local OPTIND OPTARG #Reset option flag counter
	OPTSTRING=":c:PE" #Allow flags c with arg, P or E without
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

	shift $(($OPTIND - 1)) #Shift back to the arguments
       	
	#If there's a note, add that
	if [[ "$2" != "" ]] ; then
		echo "Adding note: $2"
		to_highlight+=("%ㄋ$2")
	fi

	#Add pattern to list of patterns to highlight
	if [ "$1" = "" ] ; then
		echo "Error: pattern to highlight must be specified"
	fi	
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
insed "s/\(happen\|occur[r]\?\(ed\|s\)\?\) on \([^.,]*\(century\|decade\|year\|month\|week\|day\|hour\|minute\|second\)\)/\1 \3/gI" #Happens on a time 
insed "s/\(\(took\|take[sn]\?\) place\) on \([^.,]*\(century\|decade\|year\|month\|week\|day\|hour\|minute\|second\)\)/\1 \3/gI" #Takes place on a time, irregular construction
	# 1e: Get rid of passive voice constructions
# Initial word list is from Matt Might's shell scripts, not sure what licensing there is for compiled lists of words
irreg=$(cat "irregular_passive_verbs.txt")
hladd -c "$passive" "\\b\(am\|are\|were\|being\|is\|been\|was\|be\)\\b\(\\w\+\|\($irreg\)\)\\b" "1e: Get rid of passive voice constructions"

	# 1f: Cite all images, methods, software, and empirical data (Out of scope)

## Section 2: Enhancing clarity
	# 2a: Be concise and direct (Out of Scope)
	# 2b: Using "very" suggest that a better word exists; replace it where possible
hladd "\\b[Vv]ery\\b" "2b: Using 'very' suggest that a better word exists; replace it where possible"
	# 2c: Make sure that articles such as a, the, some, any, and each appear where necessary (Out of Scope: define where is necessary)
	# 2d: Ensure all subjects match the plurality of their verbs ("Apples is tasty" to "Apples are tasty") (Not Yet in Scope: define plurals)
	# 2e: Recover noun-ified verbs ('obtain estimates of' -> 'estimates')
hladd -c "$passive" "\(obtain\|provide\|secure\|allow\|enable\)\(s\|ed\)\?\( [^ .]*\)\{1,3\} \(of\|for\)" "2e: Recover noun-ified verbs ('obtain estimates of' -> 'estimates')" 
	# 2f: Use the form <noun> <verb>ion over <verb>ion of <noun> (for example, convert "calculation of velocity" to "velocity calculation").
hladd -c "$passive" "[a-z]ion of\\b" "2f: Use the form <noun> <verb>ion over <verb>ion of <noun> (for example, convert 'calculation of velocity' to 'velocity calculation')." 
	# 2g: Reduce vague words like important or methodologic (TODO: Add more such salt and pepper words)
insed -CD "\(various\|a number of\|many\|quite\|a few\|methodologic\(al\)\?\|important\)" 
	# 2h: Reduce acronyms/jargon
hladd -c "$misuse" " \([A-Z][a-z]\?\.\?\)\{2,\} " "2h: Reduce acronyms/jargon" #TODO: decide how separate acronyms have to be from other words
	# 2i: Expand all acronyms on first use (Out of Scope: at most, would specially highlight the first one)
	# 2j: Turn negatives into positives (she was not often right -> she was usually wrong)
hladd -c "$passive" "\\bnot\\b" "2j: Turn negatives into positives (she was not often right -> she was usually wrong)" 
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
hladd -c "$restruct" "\.[^,.;]\+\(\(,[^,.;:]\+\)\{3,\}\|\(;[,.;:]\+\)\{2,\}\):" "3f Check that if there's a list in a sentence, it shouldn't come before the colon" 
	# 3g Always use isotopic notation like '`$^{239}Pu$`. Never `$Pu-239$` or `$plutonium-239$`.'

# Elemental data; should be parallel by index

elemcsv="elements.csv"
elem_symblist=$(awk -F ',' '{if (NR>1) {print $3}}' $elemcsv) #List of symbs separated by space
read -r -a elem_symblist <<< "$elem_symblist" #Convert it to an array
elem_namelist=$(awk -F ',' '{if (NR>1) {print $2}}' $elemcsv) #Likewise but for the names
read -r -a elem_namelist <<< "$elem_namelist"
for i in ${!elem_symblist[@]}; do # Iterate through each row of element data (symbol and name)
	symb=${elem_symblist[$i]}
	name=${elem_namelist[$i]}
	#Substitute instances of element_name-number to element_symb-number
	insed "s/$name\([ -][0-9]\{1,3\}\)/$symb\1/gI"
	#Put instances of elemen_symb-number in proper isotopic notation ^{number}element_symb
	insed "s/$symb[ -]\([0-9]\{1,3\}\)/^{\1}$symb/g"
	#Put instances of isotopic notation into math mode
	insed ":repeat;s/^\(\([^$]*\$[^$]*\$\)*[^$]*\)\(\^{[0-9]\{1,3\}}[ ]\?$symb\)/\1$\3$/g;t repeat"
done

	# 3h: Strengthen your verbs (use sparingly: is, are, was, were, be, been, am) (Redundant: covered by 1e)
	# 3i: Only use 'large' when referring to size (TODO: improve with perl lookeaheads)
hladd -c "$posdel" "large" "3i: Only use 'large' when referring to size" 
	# 3j: Do not use the word "when" unless referring to a time (try 'if' instead). (TODO: improve with perl lookaheads)
hladd -c "$posdel" "when" "3j: Do not use the word 'when' unless referring to a time (try 'if' instead)." 
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
for i in ${!elem_symblist[@]}; do # iterate through each row of element data (symbol and name)
	symb=${elem_symblist[$i]}
        name=${elem_namelist[$i]}
	#If the lowercase of the element isn't commonly used, replace any lowercase instances with capitalized
	symb_with_other_uses=" He Be In Mg Co As Dy Bi Am No "
       	symbs_are_words=" He Be In Mg As " 	
	lower=$(echo "$symb" | sed 's/^\([A-Z]\)/\l\1/g') #Get the lowercase form of the symbol
	if [[ ! "$misread" =~ " $symb " ]]; then #If the lowercase isn't used as a word elsewhere, repplace standalone lowercase instnaces
		insed "s/ $lower / $symb /g" #And replace instances of it with the symbol
	fi
	if [[ ! "$symb" == "Dy" ]]; then #Except for dy, which also appears in math environments
		insed "s/}$lower/}$symb/g" # Replace instances that are right after a }, since these are likely math / symbols
	fi
	# Make sure only elements at the start of sentences are capitalized (period end of sentence)
	insed -E "s/([^.]{4})($name)/\1\u\2/gI"
done
	# 4d: Do not use the word "where" unless referring to a location (try "such that," or "in which").
hladd -c "$posdel" "where" "4d: Do not use the word 'where' unless referring to a location (try 'such that' or 'in which')." # TODO: improve with lookaheads
	# 4e: Avoid run-on sentences
clauselen=75 #Things over this many characters are assumed to be full clauses and not just items in a list (or if it is, a list that could use refactoring)
hladd -c "$restruct" "\.\([^.]\{$clauselen,\}[,;]\)\{3,\}[^.]*\." "4e: Avoid run-on sentences" #More than 4 large clause sections in the same sentence
maxsenlen=450 #Maximum recommended sentence length 
hladd -c "$restruct" "\.[^.]\{$maxsenlen\}\." "4e: Avoid run-on sentences" #Sheer character length
	# 4f: The preposition "of" shows belonging, relations, or references. The preposition "for" shows purpose, destination, amount, or recipients. They are not interchangeable. (OOS: grammar/language processing)
	
## Section 5: Enhancing punctuation
	# 5a:  Commas and periods go inside end quotes, except when there is a parenthetical reference afterward.
insed "s/\",/,\"/g" 
insed 's/,"\(\\cite{[^\{\}]*}\)/"\1,/g' 
	# 5b: colons and semicolons go outside end quotes
insed "s/\([;:]\)\"/\"\1/g"
	# 5c: A semicolon connects two independent clauses OR separates items when the list contains internal punctuation. (OOS: grammar processing)
	# 5d: Use a colon to introduce a list, quote, explanation, conclusion, or amplification. (OOS: identifying lists reliably TODO: if they can be identified, move this to highlight)
	# 5e: The Oxford comma must appear in lists (e.g., "lions, tigers, and bears").
insed "s/\(\(,[^.,;]\+\)\{2,\}\) and/\1, and/g" #TODO: should this be left to highlighting
	# 5f: Use hyphens to join words acting as a single adjective before a noun (e.g., "well-known prankster"), not after a noun (e.g., "the prankster is well known"). (OOS: grammar provessing)
	# 5g: Two words joined by a hyphen in title case should both be capitalized.
hladd -c "$misuse" "[A-Z][a-zA-Z0-9]*-[a-zA-Z0-9]*" "5g: Two words joined by a hyphen in title case should both be capitalized." 
	# 5h: Hyphens join a prefix to a capitalized word, figure, or letter (e.g., pre-COVID, T-cell receptor, post-1800s); compound numbers (e.g., sixty-six); words to the prefixes ex, self, and all (e.g., ex-sitter, self-made, all-knowing); and words to the suffix elect (e.g., president-elect).
insed "s/\(pre\|post\) \([A-Z0-9]\)/\1-\2/g" # prefixes to capitalized words, figures, letters
#insed "s/\(\\b[A-Za-z]\) \(\)"	 # Letters as prefixes (e.g. T-Cell) TODO: work out avoidance of regular letters like a, I, while still being broad enough to work
insed "s/\(twenty\|thirty\|forty\|fifty\|sixty\|seventy\|eighty\|ninety\) \(one\|two\|three\|four\|five\|six\|seven\|eight\|nine\)/\1-\2/g" # Compound numbers from 21 to 99
insed "s/\(self\|all\|ex\) \(\\w\+\\b\)/\1-\2/g" # All words to prefixes ex self all  
insed "s/\(\\b\\w\+\) elect/\1-elect/g" # Words to suffix -elect
	# 5 misc: General punctuation goes after citations
#insed "s/\"\([.;:?!]\)\(\\b\?\\\cite{[^{}]}\)/\"\2\1/g" 
insed 's/\([.;:?!]\)\(\b\?\\cite{[^\{\}]*}\)/\2\1/g'

## Section 6: Using Latin
	# 6a: The Latin abbreviations viz., i.e., and e.g. should all have commas before and after them (e.g., "We can classify a large star as a red giant, e.g., Stephenson 2-18").
insed "s/,\?\(viz\.\|i\.e\.\|i\.e\.\),\?/,\1,/g" 
	# 6b: The Latin abbreviations cf., et al., or q.v. should not automatically have commas after them.
hladd -c "$posdel" "\(cf\|et al\|q\.v\)\.," "6b: The Latin abbreviations cf., et al., or q.v. should not automatically have commas after them."
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
hladd -c "$restruct" "_{[^\{\}]*}" "8b: Subscripts should be brief and can be avoided with common notation. For example, \`\$\dot{m}\$\` is better than \`\$m_f\$\` which is superior to \`\$m_{flow}\$\`."
	# 8c: Variable names should be symbols rather than words `m` is better than `mass` and `\ksi` is better than `one_time_use_variable`. (OOS: identifying words that are variables)
	# 8d: The notation `$3.0\times10^{12}$` is preferred over `$3e12$`.
insed "s/\([0-9]\)e\([0-9]\+\)/\1\\\times10\^{\2}/g" 
	# 8e: Equations should be part of a sentence.
hl_color='brown'
insed "s/\(\\\begin{\(equation\|align\|gather\|multiline\)[*]\+}\)\(*\)\(\\\end{\2\)/\1\\\colorbox{$hl_color}{\$\\\displaystyle \3\$}\4/g" #Special highlight needed to respect math environment; this highlights equations which come right after a period
	# 8f: Equations should be in the `align` environment. Align them at the `=` sign.
insed "s/\(\.[!.]*\.\)\(\\b\\\begin{\(equation\|align\|gather\|multiline\)[*]\+}\)\(*\)\(\\\end{\3\)/\\\colorbox{$hl_color}{\1}\2\\\colorbox{$hl_color}{\$\\\displaystyle \4\$}\5/g" #Special highlight needed to respect math environment; this highlights equations which come right after a period
	# 8g: Variables should be defined in the 'align' environment, not buried in paragraphs (OOS: identifying variables)

echo "Running latexdiff:"

## Run latexdiff to generate a new copy which demonstrates the changes actively made
while IFS= read -r line; do 
	# Each line is a file address from the input dir
	
	# If it has its own new directories, create those as necessary
	subdir=$(dirname "$line")
	#echo "$subdir"
	if [ "$subdir" != "" ] ; then
		mkdir -p "$diff_dir$subdir"
	fi
	
	# Make the diff file if it's a tex file, otherwise just straight copy 
	if [[ "$line" =~ .tex$ ]] 
       	then
		latexdiff "$input_dir$line" "$edit_dir$line" > "$diff_dir$line"
		echo "Making diff for: $line"
	else
		cp "$input_dir$line" "$diff_dir$line"
		echo "Copying: $line"
	fi
done <<< "$files"


#latexdiff "$1" "$output_full" > "$output_diff"
#find "${input_dir}" -name "*.tex" -exec sh -c 'latexdiff "{}" "$edit_dir$(basename {})" > "$diff_dir$(basename {})"'  \;
#for file in "${texfiles[@]}"
#do
#	latexdiff "${input_dir}${file}" "${edit_dir}${file}" > "${diff_dir}${file}"
#done

echo "Running highlights:"
## Apply highlights to the diff file

# Make ids out of combinations of zhuyin/bopomofo characters and armenian alphabet characters, because why on god's green earth would someone's paper specifically contain pairs of these
hl_ids_bpmf='ㄅ ㄉ ㄓ ㄚ ㄞ ㄢ ㄦ ㄆ ㄊ ㄍ ㄐ ㄔ ㄗ ㄧ ㄛ ㄟ ㄣ ㄇ ㄋ ㄎ ㄑ ㄕ ㄘ ㄨ ㄜ ㄠ ㄤ ㄈ ㄌ ㄏ ㄒ ㄖ ㄙ ㄩ ㄝ ㄡ ㄥ'
hl_ids_armn='ա բ գ դ ե զ է ը թ ժ ի լ խ ծ կ հ ձ ղ ճ մ յ ն շ ո չ պ ջ ռ ս վ տ ր ց ւ փ ք օ ֆ'
read -ra bpmf_list <<< "$hl_ids_bpmf"
read -ra armn_list <<< "$hl_ids_armn"
num_bps=${#bpmf_list[@]}
num_ars=${#armn_list[@]}
# Parameter 1: Integer number of the ID to get
function bpmf_armn_id () { # Reliable combination of a zhuyin and armenian character to make an ID that can be inserted into a document for later without tripping any further patterns
        bp_idx=$(($1 / $num_bps))
        ar_idx=$(($1 % $num_ars))
	bpar_id="${bpmf_list[$bp_idx]}${armn_list[$ar_idx]}"
	echo "$bpar_id"
}


hl_color='red' #Red by default
mode='B' #BRE by default
note='' #By default, no note to add

#Save the final notes to do at the end, because text in notes could be mistaken for source text
noteText_list=()
next_noteText_idx=0
#Iterate through each highlight instruction
for instr in "${to_highlight[@]}"
do
	#echo "$instr"
	if [[ "$instr" =~ ^% ]] ; then #Some kind of special instruction like color or mode
		#echo "Special instruction: $instr"	
		if [[ "$instr" =~ ^%# ]] ; then #Specifically a mode instructor
			mode="${instr#'%#'}"
		elif [[ "$instr" =~ ^%ㄋ ]] ; then #Specifically a note instructor
			next_noteText_idx=${#noteText_list[@]} #Because zero indexing, the next index for adding this note text is the current size of the list
			echo "Adding at index $next_noteText_idx"
			noteText="${instr#'%ㄋ'}" #Text of the note
			id=$(bpmf_armn_id $next_noteText_idx) #Find the id for the index it'll be added at
			noteText_list+=("$noteText") #Add the note text to the list (at that index)
			echo "Adding note \"$noteText\" using identifier $id"
			note="\\\footnote{$id}" #If a note is specified, then build a footnote using the temporary note ID
		else #Otherwise, a color instruction
			hl_color="${instr#'%'}"
		fi
	else # If not a special instruction, then the pattern to highlight
		#echo "$instr"
		#echo "$note"
		#note=$(echo "$note" | sed "s/^#/\\\#/g;s/\([^\\]\)#/\1\\\#/g") #Since using hashtags as delimiters, make sure any hashtags in the note are escaped
		case "${mode}" in
			[bB]) #BRE
				find "$diff_dir" -type f -name "*.tex" -exec sed -i "s#\($instr\)#\\\colorbox{$hl_color}{\1}$note#g" {} \;
				;;
			[pP]) #PCRE
				note=$(echo "$note" | sed 's/\([{}]\)/\\\1/g' ) #If not BRE, need to escape the brackets
				find "$diff_dir" -type f -name "*.tex" -exec perl -i -p -e "s#($instr)#\\\colorbox\{$hl_color\}\{\1\}$note#g" "$diffile"
				;;
			[eE]) #ERE
				note=$(echo "$note" | sed 's/\([{}]\)/\\\1/g' ) #If not BRE, need to escape the brackets
				find "$diff_dir" -type f -name "*.tex" -exec sed -i -E "s#($instr)#\\\colorbox\{$hl_color\}\{\1\}$note#g" "$diffile"
				;;
		esac
		#Reset to default color and mode
		hl_color='red'
		mode='B'
		note=''
	fi	
done

#Replace each temporary identifier with the actual note
num_notes=${#noteText_list[@]}
for ((i=0;i<num_notes;i++)); do 
	#Identify the text of the note, and the temporary id that corresponds to it
	noteText="${noteText_list[$i]}"
	temp_ID="$(bpmf_armn_id $i)"
	#Find instances of that temporary id and replace with the original note text
	noteText=$(echo "$noteText" | sed "s/^#/\\\#/g;s/\([^\\]\)#/\1\\\#/g") #Since using hashtags as delimiters, make sure any hashtags in the note are escaped
	find "$diff_dir" -type f -name "*.tex" -exec sed -i "s#$temp_ID#$noteText#g" {} \; #Go through each file and replace instances of that id with the original text
	echo "Replacing id $temp_ID with original text: $noteText"
done

#TODO: Do we want to provide command line summaries? E.g. how many different instances of punctuation were used, average sentence length, commonly used words?



exit
