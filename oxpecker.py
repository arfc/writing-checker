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
    - (r'#it follows that (...)', r'#\1') to replace "...end. It follows that you can read" with "...end. YOU can read"
    - (r'#it follows that (.)(..)', r'#\1\2') to replace "...end. It follows that you can read" with "...end. You can read"
    - (r'#i#t follows that (.)(.)', r'#\1#\2') to replace "...end. IT follows that you can read" with "...end. YOu can read", but not replace "...end. It follows that you can read" with "...end. YOu can read"
'''
def add_edit(pattern:str, replace:str, allowed_envs:list[str]=[""], allowed_nodes:list=[], forbidden_nodes:list=None, capital_char:str=None):
    if (not capital_char is None):
        upper_pat = re.sub(fr'{capital_char}([a-z])',lambda m: m.group(1).upper(), pattern)
        def upper_rep(m):
            new_repl:str = replace
            for i in range(10): #For each possible capture group 0-9
                #First, check for capitalized versions
                new_repl = new_repl.replace(capital_char+f"\\{i}", m.group(i).upper())
                #Then, substitute any uncapitalized ones
                new_repl = new_repl.replace(f"\\{i}", m.group(i))
            return new_repl

        edits.append(RegexEdit(upper_pat, upper_rep, allowed_envs=allowed_envs, allowed_nodes=allowed_nodes, forbidden_nodes=forbidden_nodes))
        edits.append(RegexEdit(pattern.replace(capital_char,''), replace.replace(capital_char,''), allowed_envs=allowed_envs, allowed_nodes=allowed_nodes, forbidden_nodes=forbidden_nodes))
    else:
        edits.append(RegexEdit(pattern, replace, allowed_envs=allowed_envs, allowed_nodes=allowed_nodes, forbidden_nodes=forbidden_nodes))
        

def highlight(pattern:str, color:str, note:str=None, allowed_envs = [""], allowed_nodes = [], forbidden_nodes = ["DIFdel", "footnote", "colorbox"]):
    edits.append(RegexHighlight(pattern, color, note=note, allowed_envs=allowed_envs, allowed_nodes=allowed_nodes, forbidden_nodes=forbidden_nodes))

# Style guide & highlight colors: 
#  - red for things that should be removed, but can't automatically do so
#  - purple for likely passive voice (both in general but also stuff like "there are people who believe" instead of "some people believe"
#  - pink for things that should be removed, but can't reliably be identified
#  - brown for weird things that could use restructuring
#  - teal for things that are frequently misused (i.e large with something not about size, when with something not about time, words like code input output, verbs with data, or miscapitalization, or mistyping latin expressions)
DELETE='red'
PASSIVE='violet'
POSDEL='pink'
RESTRUCT='brown'
MISUSE='teal'

# add_edit(r'e', r'EE')
# highlight(r'hEE', 'red', 'is now the best time to HEEHEE?')

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
highlight(fr'\b(am|are|were|being|is|been|was|be)\b([a-zA-Z]+(ed)|{irreg})\b', PASSIVE, note="1e: Get rid of passive voice constructions")

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
