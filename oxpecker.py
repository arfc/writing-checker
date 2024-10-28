from pylatexenc.latexwalker import LatexWalker, LatexEnvironmentNode
import sys, os, glob
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
args = parser.parse_args()

input_path:StopAsyncIteration
if (args.path is None): #No input directory specified
    print("No input path specified, using directory './input/'")
    input_path = DEFAULT_INPUT
else:
    input_path = './' + args.path
    if not input_path[-1] == '/':
        input_path = input_path + '/'
print("Operating on files in path: " + input_path)
if (not os.path.isdir(input_path)):
    print(f"Path '{input_path}' not found, exiting.")
    exit()
print("Files in directory: ",glob.glob(input_path+'*'))
print("TeX files in directory: ", glob.glob(input_path+'**/*.tex', recursive=True))

# Set up output directories
if input_path == DEFAULT_INPUT:
    output_path = DEFAULT_OUTPUT
else:
    output_path = input_path[:len(input_path)-1] + '_pecked/'
diff_path = output_path + "diff/"
edit_path = output_path + "edit/"
print(f"Sending edits to '{edit_path}', diffs to '{diff_path}'")

#TODO: Set up a walker to build a list of all the input files to traverse

#TODO: Utility function to use latexwalker and control edits in/out of math or other environments
#TODO: Highlighting and editing functions analogous to original bash, in more open ended framework (and using utility/walker function to control applicable environments)
#TODO: Highlights and edits organized like the checklist, as in original bash
#TODO: Generate diff files
#TODO: Perform highlights on diff files, walking and reloading after each highlight to ensure no 