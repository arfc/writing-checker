from pylatexenc.latexwalker import LatexWalker, LatexEnvironmentNode
import pylatexenc as ple
import pylatexenc.latexwalker as plw
import pylatexenc.macrospec as plms
import sys, os, glob, shutil
import regex as re
from abc import ABC, abstractmethod
#Path navigation?
from pathlib import Path
#Better arg parsing
import argparse

DEFAULT_INPUT:str = './input/'
DEFAULT_OUTPUT:str = './output/'

#Step 0: Identify what set of files are being operated on
# args = sys.argv
parser = argparse.ArgumentParser()
parser.add_argument('-p', '--path', help="Path to input folder. If unspecified, looks for a folder 'input'")
parser.add_argument('-v', '--verbose', action='store_true', help="Whether to print more extensive information about the operation")
args = parser.parse_args()

verbose:bool = args.verbose
#Method to print only if verbose printing is desired
def vprint(*printable):
    if verbose:
        print(*printable)

input_path:str
if (args.path is None): #No input directory specified
    print("No input path specified, using directory './input/'")
    input_path = DEFAULT_INPUT
else:
    input_path = './' + args.path
    if not input_path[-1] == '/':
        input_path = input_path + '/'
vprint("Operating on files in path: " + input_path)
if (not os.path.isdir(input_path)):
    print(f"Path '{input_path}' not found, exiting.")
    exit()

all_paths:list[str] = glob.glob(input_path+'**', recursive=True)
tex_paths:list[str] = glob.glob(input_path+'**/*.tex', recursive=True)
vprint("Files in directory: ",all_paths)
vprint("TeX files in directory: ",tex_paths)

# Set up output directories
if input_path == DEFAULT_INPUT:
    output_path = DEFAULT_OUTPUT
else:
    output_path = input_path[:len(input_path)-1] + '_pecked/'
diff_path = output_path + "diff/"
edit_path = output_path + "edit/"
vprint(f"Sending edits to '{edit_path}', diffs to '{diff_path}'")
shutil.copytree(input_path, edit_path, dirs_exist_ok=True)
shutil.copytree(input_path, diff_path, dirs_exist_ok=True)

path_prefix:re.Pattern = re.compile(rf'^{input_path}')
for i in range(len(all_paths)):
    editpath:str = re.sub(path_prefix, output_path, all_paths[i])

edit_tex_paths:list[str] = []
diff_tex_paths:list[str] = []
for path in tex_paths:
    editpath:str = re.sub(path_prefix, edit_path, path)
    diffpath:str = re.sub(path_prefix, diff_path, path)
    edit_tex_paths.append(editpath)
    diff_tex_paths.append(diffpath)

vprint(edit_tex_paths)

#Integer tags for whether an edit should modify edit files or diff files
NO_FILES:int = 0
EDIT_FILES:int = 1
DIFF_FILES:int = 2
class TexEdit():

    def edit_files(paths:list[str], tex_paths:list[str]):
        raise NotImplementedError("TexEdit implementation should specify how files are to be edited")

    '''
    A method to recursively iterate through the provided nodes, running the given method with each node and prior context as parameters

    Parameters:
     - nodes: a list of LatexNode instances, which the method will recursively iterate through
     - method: a method which will be run for each node, with the following signature:
        ⁰ method(node:LatexNode, context:list)
        ⁰ context is a list of every parent node 
     - context: the context of prior nodes. End user should not need to provide; mostly used by the method itself in recursion 
     - run_method_on_types: a list of node types that the method can be run on. By default, only LatexCharsNode
    '''
    def iterate_nodes(self, nodes:list[plw.LatexNode], method, context:list=[], path:str=None, run_method_on_types:list=[plw.LatexCharsNode]):
        for node in nodes:
            if node is None:
                continue
            node_type = node.nodeType()
            new_context:list = context[:]
            new_context.append(node)
            if node_type in run_method_on_types:
                method(node, new_context)
            
            #If node is of a recursive kind, recursively call on each of its nodes
            if hasattr(node, 'nodelist'):
                self.iterate_nodes(node.nodelist, method, context=new_context, path=path, run_method_on_types=run_method_on_types)
            #Macro nodes can also sometimes have recursive nodes, but its tricky
            if node_type == plw.LatexMacroNode:
                m_node:plw.LatexMacroNode = node
                args:plms.ParsedMacroArgs = m_node.nodeargd
                if not args is None:
                    self.iterate_nodes(args.argnlist, method, context=new_context, path=path, run_method_on_types=run_method_on_types)

    def sync_charsnode_changes(self, nodes:list[plw.LatexNode], changed_node:plw.LatexCharsNode):
        old_fullraw = changed_node.parsing_state.s
        new_fullraw = old_fullraw[:changed_node.pos] + changed_node.chars + old_fullraw[changed_node.pos+changed_node.len:]

        changed_node.parsing_state.s = new_fullraw

        len_change:int = len(new_fullraw) - len(old_fullraw)
        if not len_change == 0:
            changed_node.len += len_change
            self.shift_nodes(nodes, changed_node.pos, len_change)



    def shift_nodes(self, nodes:list[plw.LatexNode], start_idx:int, amount:int):
        for node in nodes:
            if node == None:
                continue
            if node.pos <= start_idx and node.pos+node.len >= start_idx:
                node.len += amount
            elif node.pos >= start_idx:
                node.pos += amount
            
            if hasattr(node, 'nodelist'):
                self.shift_nodes(node.nodelist, start_idx, amount)
            elif node.nodeType() == plw.LatexMacroNode:
                m_node:plw.LatexMacroNode = node
                args:plms.ParsedMacroArgs = m_node.nodeargd
                if not args is None:
                    self.shift_nodes(args.argnlist, start_idx, amount)

    def is_highlight() -> bool:
        return False



class RegexEdit(TexEdit):
    DEFAULT_ALLOWED_NODES:list = [plw.LatexCharsNode, plw.LatexGroupNode, plw.LatexEnvironmentNode]
    DEFAULT_ALLOWED_ENVS:list[str] = ['document', 'center', 'left', 'justified', 'right']
    
    

    def __init__(self, pattern:str, replace:str, allowed_envs:list[str]=[""], allowed_nodes:list=[], forbidden_nodes:list=None):
        self.pattern = pattern
        self.replace = replace
        self.allowed_envs = allowed_envs
        self.allowed_nodes = allowed_nodes
        self.allowed_nodes.extend(RegexEdit.DEFAULT_ALLOWED_NODES)

        #Screening mode: by default, operates on a whitelist, where only listed nodes are allowed. If 'blacklist' is true, operates on a blacklist, where anything is allowed except for certain specified nodes
        if forbidden_nodes is None:
            self.blacklist:bool = False
        else:
            self.blacklist:bool = True
            self.forbidden_nodes = forbidden_nodes
        
    #Makes new walker every time, because each edit should incorporate previous edit's changes
    def edit_files(self, paths, tex_paths):
        for path in tex_paths:
            with open(path) as tex_file:
                walker:LatexWalker = LatexWalker(tex_file.read())
        
            nodes:list[plw.LatexNode] = walker.get_latex_nodes()[0]

            def edit_node(node:plw.LatexCharsNode, context:list[plw.LatexNode]):
                for parent in context:
                    p_type = (parent.nodeType())
                    # Make sure that all parental nodes are allowed, either by using a whitelist or a blacklist
                    if ((not self.blacklist) and not p_type in self.allowed_nodes) or (self.blacklist and p_type in self.forbidden_nodes):
                        return
                
                node.chars = re.sub(self.pattern, self.replace, node.chars)
                self.sync_charsnode_changes(nodes,  node)
                

            self.iterate_nodes(nodes, edit_node)

            updated_raw:str = ""
            for base_node in nodes:
                updated_raw += base_node.latex_verbatim()
            
            with open(path, 'w') as tex_file:
                tex_file.write(updated_raw)

# An extension of RegexEdit which specifically adds a colorbox highlight and a footnote to mark things that should be corrected, but can't be automatically
# By default, uses a blacklist instead of a whitelist, to forbid DIFdel nodes
class RegexHighlight(RegexEdit):
    def __init__(self, pattern:str, color:str, note:str=None, allowed_envs = [""], allowed_nodes = [], forbidden_nodes = ["DIFdel", "footnote", "colorbox"]):
        pattern = '('+pattern+')'
        replace = r'\\colorbox{'+color+r'}{\1}'
        if not note is None:
            replace = replace +r'\\footnote{'+note+r'}'
        super().__init__(pattern, replace, allowed_envs, forbidden_nodes=forbidden_nodes)

# Main list of edits, organized alongside the checklist    
edits:list[TexEdit] = []
diff_edits:list[TexEdit] = []

#Methods to quickly add the most common edits to the stack
'''
A method to more efficiently add RegexEdits to the edit stack.

Parameters:
- pattern: the regex pattern string for the edit to use (if not using the capitalization feature of this function, this can be a precompiled regex pattern)
- replace: the regex replace string for the pattern to substitute (if not using the capitalization feature of this function, this can be an arbitrary replace function)
- allowed_envs, allowed_nodes, forbidden_nodes: Arguments identical to those of RegexEdit, which specify where this edit can take place. See RegexEdit for how these are specfically applied

To add capitalizations, pass a character such as '#' as parameter "capital_char":
- Put that character in front of the character in the (lowercase) character to match hypothetical capitalization of
- Put that character in front of the/each group in the replace string that should subsequently be capitalized if the pattern's character(s) is/are capitalized
- E.g.: 
    - (r'#it follows that (.)', r'#\1') to replace "...end. It follows that you can read" with "...end. You can read", or "so it follows that you" with "so you"
    - (r'#it follows that (...)', r'#\1') to replace "...end. It follows that you can read" with "...end. You can read"
    - (r'#it follows that (.)(..)', r'#\1#\2') to replace "...end. It follows that you can read" with "...end. YOu can read"
    - (r'#i#t follows that (.)(.)', r'#\1#\2') to replace "...end. IT follows that you can read" with "...end. YOu can read", but not replace "...end. It follows that you can read" with "...end. YOu can read"
'''
def add_edit(pattern:str, replace:str, allowed_envs:list[str]=[""], allowed_nodes:list=[], forbidden_nodes:list=None, capital_char:str=None):
    if (not capital_char is None):
        upper_pat = re.sub(fr'{capital_char}([a-z])',lambda m: m.group(1).upper(), pattern)
        def upper_rep(m):
            new_repl:str = replace
            for i in range(10): #For each possible capture group 0-9
                #First, check for capitalized versions
                capital_group:str = capital_char+f"\\{i}"
                if (capital_group in new_repl):
                    capitalized_group = m.group(i)
                    capitalized_group[0] = capitalized_group[0].upper()
                    new_repl = new_repl.replace(capital_char+f"\\{i}", capitalized_group)
                #Then, substitute any uncapitalized ones
                reg_group:str = f"\\{i}"
                if (reg_group in new_repl):
                    new_repl = new_repl.replace(f"\\{i}", m.group(i))
                #Finally, capitalize any individually marked characters in the repl
                new_repl = re.sub(fr'{capital_char}([a-z])',lambda m: m.group(1).upper(), new_repl)
            return new_repl

        edits.append(RegexEdit(upper_pat, upper_rep, allowed_envs=allowed_envs, allowed_nodes=allowed_nodes, forbidden_nodes=forbidden_nodes))
        edits.append(RegexEdit(pattern.replace(capital_char,''), replace.replace(capital_char,''), allowed_envs=allowed_envs, allowed_nodes=allowed_nodes, forbidden_nodes=forbidden_nodes))
    else:
        edits.append(RegexEdit(pattern, replace, allowed_envs=allowed_envs, allowed_nodes=allowed_nodes, forbidden_nodes=forbidden_nodes))
        

def highlight(pattern:str, color:str, note:str=None, allowed_envs = [""], allowed_nodes = [], forbidden_nodes = ["DIFdel", "footnote", "colorbox"]):
    diff_edits.append(RegexHighlight(pattern, color, note=note, allowed_envs=allowed_envs, allowed_nodes=allowed_nodes, forbidden_nodes=forbidden_nodes))

# Style guide & highlight colors: 
#  - red for things that should be removed, but can't automatically do so
#  - purple for likely passive voice, or otherwise strengthening statements (stuff like "there are people who believe" instead of "some people believe", or using a better word instead of "very [x]")
#  - pink for things that should be removed, but can't reliably be identified
#  - brown for weird things that could use restructuring
#  - teal for things that are frequently misused (i.e large with something not about size, when with something not about time, words like code input output, verbs with data, or miscapitalization, or mistyping latin expressions)
DELETE='red'
PASSIVE_WEAK='violet'
UNCLEAR='blue'
POSSIBLY_DELETE='pink'
RESTRUCT='brown'
MISUSE='teal'

# add_edit(r'e', r'EE')
# highlight(r'hEE', 'red', 'is now the best time to HEEHEE?')


####################################################################################################################################################################################################################################################
#  THE CHECKLIST  ##################################################################################################################################################################################################################################
####################################################################################################################################################################################################################################################


## Section 1: Reviewing Writing
	# 1a: Spell Checker (Out of scope)
	# 1b: Get rid of unnecessary propositional phrases -- author clearing throat
add_edit(r'#it (follows|can be shown|seems|seems reasonable|is evident|is apparent|happens|occurs) that[,]?[ ]+(.)', r'#\2', capital_char='#')
    # 1c: Get rid of there are/there is
highlight(r'there (is|are|exist[s]?|(can|may) be)', DELETE, note="1c: Get rid of there are/there is")
    # 1d: Extraneous prepositions
add_edit(r'((happen|occur[r]?)(ed|s)?|took|take[sn]?) on ([^.,]*(century|decade|year|month|week|day|hour|minute|second))', r'\1 \4')
    # 1e: Get rid of passive voice constructions
with open('irregular_passive_verbs_ERE.txt', 'r') as irreg_file:
    irreg = irreg_file.read().replace('\n','')
    print(irreg)
highlight(fr'\b(am|are|were|being|is|been|was|be)\b([a-zA-Z]+(ed)|{irreg})\b', PASSIVE_WEAK, note="1e: Get rid of passive voice constructions")
    # 1f: Cite all images, methods, software, and empirical data (Currently out of scope)

## Section 2: Enhancing clarity
	# 2a: Be concise and direct (Out of Scope, unless we gather a bunch more specific examples of fluff)
    # 2b: Using "very" suggest that a better word exists; replace it where possible
highlight(r'\b[Vv]ery\b', PASSIVE_WEAK, note="2b: Using 'very' suggest that a better word exists; replace it where possible")
    # 2c: Make sure that articles such as a, the, some, any, and each appear where necessary (Out of Scope: define where is necessary)
	# 2d: Ensure all subjects match the plurality of their verbs ("Apples is tasty" to "Apples are tasty") (Not Yet in Scope: define plurals)
	# 2e: Recover noun-ified verbs ('obtain estimates of' -> 'estimates')
highlight(r'(obtain|provide|secure|allow|enable)(s|ed)?( [^ .]*){1,3} (of|for)', PASSIVE_WEAK, "2e:  Recover noun-ified verbs ('obtain estimates of' -> 'estimates')")
    # 2f: Use the form <noun> <verb>ion over <verb>ion of <noun> (for example, convert "calculation of velocity" to "velocity calculation").
highlight(r'[a-z]ion of\b', PASSIVE_WEAK, note="2f: Use the form <noun> <verb>ion over <verb>ion of <noun> (for example, convert 'calculation of velocity' to 'velocity calculation').")
    # 2g: Reduce vague words like important or methodologic (TODO: Add more such salt and pepper words)
add_edit(r'(#various|#a number of|#many|#quite a few|#methodologic(al)?|#important)', r'', capital_char='#')
    # 2h: Reduce acronyms/jargon
highlight(r'([A-Z][a-z]?\.?){2,}', UNCLEAR, note="2h: Reduce acronyms/jargon")
    # 2i: Expand all acronyms on first use (Out of Scope: at most, would specially highlight the first one)
    # 2j: Turn negatives into positives (she was not often right -> she was usually wrong)
highlight(r'\bnot\b', PASSIVE_WEAK, note="2j: Turn negatives into positives (she was not often right -> she was usually wrong)")
    # 2k: Do not bury the verb, keep predicate close to subject at start of sentence (Out of Scope: Process and interpret grammar)
	# 2l: Refer to software consistently by name (TODO: Recognize and highlight generic references to 'the software')
	# 2m: Italicize unusual or unfamiliar words of phrases when you use them (OOS: Would require grammar/frequency processing)
	# 2n: If you use an uncommmon word, consider changing it or defining it in its first usage (OOS: grammar/frequency processing)

## Section 3: Enhancing Style
    # 3a: Vary your sentence structure to keep readers engaged (OOS: grammar processing)
    # 3b: Do not use contractions in technical writing
add_edit(r'I\'m', r'I am')
add_edit(r'#can\'t', r'#can not', capital_char='#')
add_edit(r'#won\'t', r'#will not', capital_char='#')
add_edit(r'(#are|#is|#do|#should|#would|#could|#have|#had|#was|#were)n\'t', r'#\1 not', capital_char='#')
add_edit(r'(#they|#you|#we)\'re', r'#\1 are', capital_char='#')
add_edit(r'(#he|#she|#it)\'s', r'#\1 is', capital_char='#')
    # 3c Use Punctuation to help you vary your sentence structure (OOS: Diagnostics)
	# 3d Follow the convention that the power to separate is (in order of increasing power): comma, colon, em dash, parentheses, semicolon, and period. (OOS: Diagnostics)
	# 3e In increasing order of formality: dash, parentheses, all others. Do not overdo the em dash and parentheses. (OOS: Diagnostics)
	# 3f Check that if there's a list in a sentence, it shouldn't come before the colon
highlight(r'\.[^,.;]+((,[^,.;:]+){3,}|(;[,.;:]+){2,}):', RESTRUCT, note="3f Check that if there's a list in a sentence, it shouldn't come before the colon") # period, any characters not a comma/semicolon or another period, either: a 4 item comma list or a 3 item semicolon list, and then a comma
    # 3g Always use isotopic notation like '`$^{239}Pu$`. Never `$Pu-239$` or `$plutonium-239$`.' TODO: decide how to handle periodic table data in the python script
    # 3h: Strengthen your verbs (use sparingly: is, are, was, were, be, been, am) (Redundant: covered by 1e)
    # 3i: Only use 'large' when referring to size (TODO: improve with perl lookeaheads)
highlight(r'large', POSSIBLY_DELETE, note="3i: Only use 'large' when referring to size")
    # 3j: Do not use the word "when" unless referring to a time (try 'if' instead). (TODO: improve with perl lookaheads)
highlight(r'when', POSSIBLY_DELETE, "3j: Do not use the word 'when' unless referring to a time (try 'if' instead).")
    # 3k: Clarify or change misused/overused words where necessary (e.g., code, input, output, different, value, amount, model). (OOS: Define list of misused or overused words)
	# 3l: Each sentence/paragraph should logically follow the previous sentence/paragraph. (OOS: Grammar/language processing)
	# 3m: Examples should use variables instead of numbers and symbolic math instead of acronyms (OOS: universally identifying such references)

## Section 4: Enhancing Grammar
	# 4a: "Data" is plural
add_edit(r'(#data) is', r'#\1 are', capital_char='#')
add_edit(r'(#data) was', r'#\1 were', capital_char='#')
add_edit(r'#this ([^ ]+\b)?data', r'#these \1data', capital_char='#') #this (room for 1 word, any more risks false positive) data
add_edit(r'(#data)( \w+ly)? (suggest|demonstrate|include|prove)s', r'#\1\2 \3', capital_char='#') #data (optional adverb) common verbs -> make sure the verb is plural
    # 4b: Compare to (point out similarities between different things) vs. compared with (point out differences between similar things) (OOS: grammar/language processing)
    # 4c: Elemental symbols (Ni, Li, Na, Pu) are capitalized, but their names are not (nickel, lithium, sodium, plutonium). TODO: decide how to handle periodic table data in the python script
    # 4d: Do not use the word "where" unless referring to a location (try "such that," or "in which").
highlight(r'where', POSSIBLY_DELETE, note='Do not use the word "where" unless referring to a location (try "such that," or "in which").')
    # 4e: Avoid run-on sentences
min_clause_len = 75 #in chars
max_clauses = 3
highlight(rf'\.([^.]{min_clause_len,}[,;]){max_clauses,}[^.]*\.', RESTRUCT, note="4e: Avoid run-on sentences") #Period, more than 4 (3+1 after) blocks of more than 45 characters separated by commas/semicolons and then another period.
max_sentence_len = 450 #in chars
highlight(rf'\.[^.\n]{max_sentence_len}\.', "4e: Avoid run-on sentences") #More than 450 characters between two periods
    # 4f: The preposition "of" shows belonging, relations, or references. The preposition "for" shows purpose, destination, amount, or recipients. They are not interchangeable. (OOS: grammar/language processing, or just a LOT of specific examples)

## Section 5: Enhancing punctuation
	# 5a:  Commas and periods go inside end quotes, except when there is a parenthetical reference afterward.
add_edit(r'",', r',"')
add_edit(r',"(\\cite\{[^{}]*\})', r'"\1,')
    # 5b: colons and semicolons go outside end quotes
add_edit(r'([;:])"', r'"\1')
    # 5c: A semicolon connects two independent clauses OR separates items when the list contains internal punctuation. (OOS: grammar processing)
	# 5d: Use a colon to introduce a list, quote, explanation, conclusion, or amplification. (OOS: identifying lists reliably TODO: if they can be identified, move this to highlight)
	# 5e: The Oxford comma must appear in lists (e.g., "lions, tigers, and bears").
add_edit(r'((,[^,.;]+){2,}) and', r'\1, and') #Should this be left to highlighting?
    # 5f: Use hyphens to join words acting as a single adjective before a noun (e.g., "well-known prankster"), not after a noun (e.g., "the prankster is well known"). (OOS: grammar processing)
	# 5g: Two words joined by a hyphen in title case should both be capitalized.
add_edit(r'([A-Z][a-zA-Z0-9]*-)([a-z])', r'\1#\2', capital_char='#')
	# 5h: Hyphens join a prefix to a capitalized word, figure, or letter (e.g., pre-COVID, T-cell receptor, post-1800s); compound numbers (e.g., sixty-six); words to the prefixes ex, self, and all (e.g., ex-sitter, self-made, all-knowing); and words to the suffix elect (e.g., president-elect).
add_edit(r'(#pre|#post) ([A-Z0-9])', r'#\1-\2')
#add_edit() # TODO: Add an add_edit() for Letters as prefixes (e.g. T-Cell), but work out avoidance of regular letters like a, I, while still being broad enough to work
add_edit(r'(#twen|#thir|#for|#fif|#six|#seven|#eigh|#nine)ty (one|two|three|four|five|six|seven|eight|nine)', r'#\1-\2', capital_char='#') # Compound numbers from 21 to 99
add_edit(r'(#self|#all|#ex) (\w+\b)', r'#\1-\2', capital_char='#')  # All words to prefixes ex self all 
add_edit(r'((#president|#senat(or|e)|#rep(resentative)?|(#congress|#council)((wo)?man|men)|#mayor|#governor|#general)[s]?) elect', r'#\1-elect') #Electable positions to suffix -elect TODO: add more electable positions
    # 5 misc: General punctuation goes after citations
add_edit(r'([.;:?!])([ ]*\\cite\{[^{}]*\})', r'\2\1')

## Section 6: Using Latin
    # 6a: The Latin abbreviations viz., i.e., and e.g. should all have commas before and after them (e.g., "We can classify a large star as a red giant, e.g., Stephenson 2-18").
add_edit(r',?(viz\.|i\.e\.|e\.g\.),?', r',\1,')
    # 6b: The Latin abbreviations cf., et al., or q.v. should not automatically have commas after them.
highlight(r'(cf|et al|q\.v)\.,', POSSIBLY_DELETE, note="6b: The Latin abbreviations cf., et al., or q.v. should not automatically have commas after them.")
    # 6c: Versus should always have a period (at least in American English)
add_edit(r'vs\.?', r'vs.')
    # 6d: "and etc." is redundant since etc. stands for *et* cetera
add_edit(r'and etc', r'etc')
    # 6e: "et" in abbreviations should not have a period, since et is a whole word
add_edit(r'et\.', r'et') #This SHOULD be fine, because I don't see where you would use et at the end of a sentence naturally
    # 6f: Some abbreviations, such as N.B., require capitalization
to_cap = [r'N\.B\.', r'CV']
for cap in to_cap:
    add_edit(to_cap, to_cap) #TODO: add way to trigger re ignore case flag
    # 6g: full latin phrases other than et should generally be italicized
add_edit(r'(?<!\{\s{1,5})(in (situ|vivo|vitro)|ab initio)(?!\s+\})', r'\\emph\{\1\}') #replace latin phrase without apparent brackets aorund it with phrase wrapped in \emph{}

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
highlight(r'_\{[^{}]*\}', RESTRUCT, note="8b: Subscripts should be brief and can be avoided with common notation. For example, \`\$\dot{m}\$\` is better than \`\$m_f\$\` which is superior to \`\$m_{flow}\$\`.")
    # 8c: Variable names should be symbols rather than words `m` is better than `mass` and `\ksi` is better than `one_time_use_variable`. (OOS: identifying words that are variables)
    # 8d: The notation `$3.0\times10^{12}$` is preferred over `$3e12$`.
add_edit(r'([^0-9a-fA-F])([0-9a-fA-F]{6}([0-9a-fA-F]{2})?)([^0-9a-fA-F])', r'\1ㄏㄎ\2\4') #Mark items that are likely hex codes
add_edit(r'(ㄏㄎ[0-9a-fA-F]{0,7})([eE])', r'\1ㄜ\2') #Mark the e's inside possible hexcodes
add_edit(r'([0-9])[eE]([0-9]+)', r'\1\\times10\^\{\2\}') #Replace non-noted e notation with full scientific notation
add_edit(r'(ㄏㄎ[0-9a-fA-F]{0,7})ㄜ', r'\1') #Remove the hexcode e marker
add_edit(r'ㄏㄎ([0-9a-fA-F]{6})', r'\1') #Remove the hexcode marker
    # 8e: Equations should be part of a sentence.
highlight(r'\.\s+(?=\\begin\{(equation|align|gather|multline))') #Period followed by spaces and then the beginning of an equation
    # 8f: Equations should be in the `align` environment. Align them at the `=` sign.
#TODO: Add this equivalent highlight from the bash script, it should work but it will take some reverse engineering
    # 8g: Variables should be defined in the 'align' environment, not buried in paragraphs (OOS: identifying variables)

####################################################################################################################################################################################################################################################
#  END CHECKLIST  ##################################################################################################################################################################################################################################
####################################################################################################################################################################################################################################################


for edit in edits: 
    edit.edit_files(edit_tex_paths, edit_tex_paths)

if not (len(edit_tex_paths) == len(diff_tex_paths) and len(edit_tex_paths) == len(tex_paths)):
    print("Edit tex paths were different than diff tex paths or base tex paths", edit_tex_paths, diff_tex_paths, tex_paths)
    exit()
for i in range(len(tex_paths)):
    b_path = tex_paths[i]
    e_path = edit_tex_paths[i]
    d_path = diff_tex_paths[i]

    command:str = f"latexdiff '{b_path}' '{e_path}' > '{d_path}'"
    print(command)
    os.system(command)

for diff_edit in diff_edits:
    diff_edit.edit_files(diff_tex_paths, diff_tex_paths)
