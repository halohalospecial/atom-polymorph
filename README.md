# Polymorph

Simultaneously edit multiple text ranges with related meanings, but different forms.

## Screenshots
Easier to explain with screenshots! :)

![case1](https://github.com/halohalospecial/atom-polymorph/blob/master/images/case1.gif?raw=true)

![case2](https://github.com/halohalospecial/atom-polymorph/blob/master/images/case2.gif?raw=true)

![redux](https://github.com/halohalospecial/atom-polymorph/blob/master/images/redux.gif?raw=true)

![cardinality](https://github.com/halohalospecial/atom-polymorph/blob/master/images/cardinality.gif?raw=true)

![verb-form](https://github.com/halohalospecial/atom-polymorph/blob/master/images/verb-form.gif?raw=true)

![color](https://github.com/halohalospecial/atom-polymorph/blob/master/images/color.gif?raw=true)

![inverse](https://github.com/halohalospecial/atom-polymorph/blob/master/images/inverse.gif?raw=true)

![xml](https://github.com/halohalospecial/atom-polymorph/blob/master/images/xml.gif?raw=true)

## Commands

### `Polymorph: Mark Next In Any Case And Form`
Marks the next text range which has a related meaning with the active selection, but has a different letter case or form.  If nothing is selected, this will select the longest "superword" under the cursor.  Invoke this multiple times to mark the next matching text ranges, similar to `Find And Replace: Select Next`.  Editing the source text range will also edit the marked ranges.  Press `escape` when you're done.

### `Polymorph: Skip Last Marked`
Unmarks the last marked text range.  Invoking `Polymorph: Mark Next In Any Case And Form` again will mark the next matching text range, skipping the unmarked one.  This command is useful if Polymorph marked an incorrect text range.

![skip](https://github.com/halohalospecial/atom-polymorph/blob/master/images/skip.gif?raw=true)

### `Polymorph: Select All Marked`
Selects all marked text ranges.

![select-marked](https://github.com/halohalospecial/atom-polymorph/blob/master/images/select-marked.gif?raw=true)

### `Polymorph: Case Preserving Paste`
Use this instead of `Core: Paste` to coerce the case of the pasted text into the case of the target selection.  For example, if the copied text is "mark-next-in-any" and the target selection is "casePreservingPaste", the pasted text will become "markNextInAny" because the target is in camel case.

![paste](https://github.com/halohalospecial/atom-polymorph/blob/master/images/paste.gif?raw=true)

### Forced Transformation Commands
These commands work on selections and ranges marked by Polymorph.

- `Polymorph: Capitalize`
- `Polymorph: Decapitalize`
- `Polymorph: Snake Case`
- `Polymorph: Screaming Snake Case`
- `Polymorph: Kebab Case`
- `Polymorph: Cobol Case`
- `Polymorph: Upcase`
- `Polymorph: Downcase`
- `Polymorph: Camel Case`
- `Polymorph: Pascal Case`
- `Polymorph: Invert`
- `Polymorph: Pluralize`
- `Polymorph: Singularize`
- `Polymorph: To Past`
- `Polymorph: To Present`
- `Polymorph: To Infinitive`
- `Polymorph: To Gerund`
- `Polymorph: To Comparative`
- `Polymorph: To Superlative`
- `Polymorph: To Noun`
- `Polymorph: To Adverb`
- `Polymorph: To Adjective`
- `Polymorph: To Color Name`
- `Polymorph: To Color Hex8`
- `Polymorph: To Color Hex6`
- `Polymorph: To Color Hex3`
- `Polymorph: To Color Rgb`
- `Polymorph: To Color Rgba`
- `Polymorph: To Color Prgb`
- `Polymorph: To Color Hsl`
- `Polymorph: To Color Hsv`

## Example keybindings
```
'atom-text-editor':
  'cmd-e': 'polymorph:mark-next-in-any-case-and-form'
  'shift-cmd-e': 'polymorph:skip-last-marked'
  'ctrl-e': 'polymorph:select-all-marked'
  'shift-cmd-v': 'polymorph:case-preserving-paste'
```

## Credits

Uses [nlp_compromise](https://www.npmjs.com/package/nlp_compromise) and [tinycolor2](https://www.npmjs.com/package/tinycolor2).

## Prior Art
After some searching, the closest I could find was [abolish.vim](http://www.vim.org/scripts/script.php?script_id=1545) by [Tim Pope](http://tpo.pe/).  That vim plugin lets you replace text by specifying some rules (e.g. `:%Subvert/facilit{y,ies}/building{,s}/g` to replace all instances of "facility" with "building" and "facilities" with "buildings").  

Polymorph attempts to figure out the rules instead, making it less precise, but more magical.
