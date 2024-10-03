from pylatexenc.latexwalker import LatexWalker, LatexEnvironmentNode
import sys, os, glob
#Path navigation?
from pathlib import Path

#Step 0: Identify what set of files are being operated on
args = sys.argv
input_path:str
if (len(args) < 2): #No input directory specified
    print("No input path specified, using directory './input/'")
    input_path = './input/'
else:
    input_path = './' + sys.argv[1]
print("Operating on files in path: " + input_path)
print("Files in directory: ",glob.glob(input_path+'*'))
print("TeX files in directory: ", glob.glob(input_path+'**/*.tex', recursive=True))
#TODO: Set up a walker to build a list of all the input files to traverse

#TODO: Utility function to use latexwalker and control edits in/out of math or other environments
#TODO: Highlighting and editing functions analogous to original bash, in more open ended framework (and using utility/walker function to control applicable environments)
#TODO: Highlights and edits organized like the checklist, as in original bash
#TODO: Generate diff files
#TODO: Perform highlights on diff files, walking and reloading after each highlight to ensure no 