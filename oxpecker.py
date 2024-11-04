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

class TexEdit():
    @abstractmethod
    def edit_files(paths:list[str], tex_paths:list[str]):
        pass

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

class TexDiffEdit():
    @abstractmethod
    def edit_diff_files(paths:list[str], tex_paths:list[str]):
        pass


class RegexEdit(TexEdit):

    

    def __init__(self, pattern:str, replace:str, allowed_envs:list[str]=[""], allowed_nodes:list=[] ):
        DEFAULT_ALLOWED_NODES:list = [plw.LatexCharsNode, plw.LatexGroupNode, plw.LatexEnvironmentNode]
        DEFAULT_ALLOWED_ENVS:list[str] = ['document', 'center', 'left', 'justified', 'right']

        self.pattern = pattern
        self.replace = replace
        self.allowed_envs = allowed_envs
        self.allowed_nodes = allowed_nodes
        self.allowed_nodes.extend(DEFAULT_ALLOWED_NODES)
        
    #Makes new walker every time, because each edit should incorporate previous edit's changes
    def edit_files(self, paths, tex_paths):
        for path in tex_paths:
            with open(path) as tex_file:
                walker:LatexWalker = LatexWalker(tex_file.read())
        
            nodes:list[plw.LatexNode] = walker.get_latex_nodes()[0]

            def edit_node(node:plw.LatexCharsNode, context:list[plw.LatexNode]):
                parent_types:list = []
                for parent in context:
                    parent_types.append(parent.nodeType())
                for p_type in parent_types:
                    if not p_type in self.allowed_nodes:
                        return
                
                node.chars = re.sub(self.pattern, self.replace, node.chars)
                self.sync_charsnode_changes(nodes,  node)
                

            self.iterate_nodes(nodes, edit_node)

            updated_raw:str = ""
            for base_node in nodes:
                updated_raw += base_node.latex_verbatim()
            
            with open(path, 'w') as tex_file:
                tex_file.write(updated_raw)
            
            
            
edits:list[TexEdit] = []
edits.append(RegexEdit(r'e', r'EE'))

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


#TODO: Set up a walker to build a list of all the input files to traverse

#TODO: Utility function to use latexwalker and control edits in/out of math or other environments
#TODO: Highlighting and editing functions analogous to original bash, in more open ended framework (and using utility/walker function to control applicable environments)
#TODO: Highlights and edits organized like the checklist, as in original bash
#TODO: Generate diff files
#TODO: Perform highlights on diff files, walking and reloading after each highlight to ensure no 