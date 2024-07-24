
## The ARFC writing Autochecklist

This repository contains the source code for an autochecklist, a bash script to edit LaTeX documents according to the group [writing checklist](https://arfc.github.io/manual/guides/writing/checklist/). This project is currenly in its early stages, and may see revision to its usage and form.

# Description

This bash script takes input of a LaTeX source directory, and processes it according to the ARFC writing checklist found at <https://arfc.github.io/manual/guides/writing/checklist/>. The original directory isn't changed, but two copies are created: an edit and a diff. The edit has a series of changes applied to it, based on the checklist items which can be automatically executed. The diff breaks down, using the program latexdiff, what these changes were. The diff also highlights, using the latex package xcolor, parts of the document which the checklist says should be changed, but either can't be automatically changed or can't be confidently identified.

# Usage

To use the script, clone the repository or download the files `w_check.sh`, `elements.csv`, and `irregular_passive_verbs.txt` into a directory. 

Then, make a subdirectory at the same level named `input`, and put the LaTeX source code you want to inspect into that directory. If you made a clone of the entire repository, there should already be an `input` directory, with an example document inside it. Remove the example if you want, and add your files to the input directory.

When the target files are in the input directory, navigate to the main directory and run the script:

`bash w_check.sh`

The script will generate two copies of the LaTeX source, in the subdirectories `output/edit/` and `output/diff`. The edit is a copy of the source with all possible changes applied to it, to be used or previewed. The diff is a copy of the source which uses latexdiff to show each change that was made. The diff also shows highlighted suggestions for more modifications, which couldn't automatically be performed.

# Repository Overview

The repository contains the script and a basic input example.

`input` is a directory where files are put to analyze. In the main repository, it currently contains an example of an input.

`w_check.sh` is the core file of the script, a bash script which makes copies of the contents of `input` into a new directory `output`.

`elements.csv` and `irregular_passive_verbs.txt` are text files with data about elements and a list of exceptions to passive verb patterns. In the future, these may be consolidated into `w_check.sh` and no longer necessary.

# Code

The script's operations are organized to match the checklist itself, for best usability and maintenance. To accomplish this, a couple of utility methods are defined:

The function "insed" takes a sed command and performs it on each tex file in the directory. Example:

`insed "s/I'm/I am/gI"` 
`insed -C "s/can't/can not/g"`

These lines expand the contractions "I'm" and "can't", respectively. Note that the both give the full sed command as the argument, but don't specify a file or whether to write the original file or print to terminal. The script does some other processing to interpret flags, but then in these cases would in effect run `sed -i -e <pattern> <file>` on each file ending in '.tex'. Flags like -C modify how this is performed, with the flag -C in this case being shorthand to automatically modify the command to account for capitalization. (Some of these flags, like -C, are redundant because they could be made in the command, but the flag makes it quicker to write and more readable afterwards)

The function "hladd" adds a pattern to a list of things to highlight, and after finishing edits and generating diff files, searches for and highlights these patterns in the diff files. For example, `hladd "red" "\\b[Vv]ery\\b"` would add a pattern searching for the word 'very' to the list, with a note to highlight it using the color named "red," changing `very` to `\colorbox{red}{very}`

Thus, the script takes the form:

1. Basic checks
2. Define utility functions
3. Edit or prepare highlights to the documents for each checklist item
4. Generate diff files between the original and edit using latexdiff
5. Apply the prepared list of highlights to the diff files
